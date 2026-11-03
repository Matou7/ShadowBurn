// lib/screens/arena_tv_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ArenaTvScreen extends StatefulWidget {
  const ArenaTvScreen({super.key});

  @override
  State<ArenaTvScreen> createState() => _ArenaTvScreenState();
}

class _ArenaTvScreenState extends State<ArenaTvScreen> with WidgetsBindingObserver {
  String? _roomId;
  String? _adminKey;
  String? _joinToken;
  String? _instanceToken;
  DocumentReference? _raidRef;
  StreamSubscription? _raidSubscription;

  Timer? _localTickTimer;
  Timer? _arenaHeartbeatTimer;
  Timer? _queueRetryTimer;

  Map _raidData = {};
  bool _isRaidDataLoaded = false;

  int _targetEndTimeMs = 0;
  int _remainingSeconds = 0;
  bool _isAllocating = true;
  bool _isWorldSaturated = false;
  bool _isNightLockActive = false;
  bool _isDespawnedForInactivity = false;

  String _currentRaidStatus = 'waiting';
  double _currentBossHp = 5000.0;

  int _lastRoomActivityMs = 0;
  int _idleSecondsElapsed = 0;
  int _lastKnownHunterCount = 0;
  double _lastKnownHp = 5000.0;
  String _lastKnownStatus = 'waiting';

  static const int kMaxGlobalRooms = 100;
  static const int kMaxHuntersPerRoom = 10;
  static const int kHeartbeatIntervalSeconds = 20;
  static const int kRoomDeathThresholdMs = 60000;
  static const int kMaxInactivitySeconds = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastRoomActivityMs = DateTime.now().millisecondsSinceEpoch;

    _localTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final now = DateTime.now();
      // VERROUILLAGE NOCTURNE : Fermé de 00:00 à 06:00 du matin
      bool isNightClosed = now.hour >= 0 && now.hour < 6;
      if (isNightClosed != _isNightLockActive) {
        setState(() {
          _isNightLockActive = isNightClosed;
        });
        if (isNightClosed) {
          _despawnAndStopAllTimers();
          return;
        }
      }

      if (!_isAllocating && !_isWorldSaturated && !_isNightLockActive && !_isDespawnedForInactivity) {
        final int nowMs = now.millisecondsSinceEpoch;
        _idleSecondsElapsed = ((nowMs - _lastRoomActivityMs) ~/ 1000).clamp(0, 9999);

        if (_idleSecondsElapsed >= kMaxInactivitySeconds &&
            (_currentRaidStatus == 'waiting' || _currentRaidStatus == 'active')) {
          _triggerInactivityDespawn();
          return;
        }
      }

      if (_targetEndTimeMs > 0 && !_isDespawnedForInactivity && !_isNightLockActive) {
        final nowMs = now.millisecondsSinceEpoch;
        final diff = (_targetEndTimeMs - nowMs) ~/ 1000;
        final remaining = diff > 0 ? diff : 0;

        setState(() {
          _remainingSeconds = remaining;
        });

        if (remaining == 0 && _currentRaidStatus == 'active' && _currentBossHp > 0) {
          _triggerDefeat();
        }
      }
    });
  }

  void _recordActivity() {
    _lastRoomActivityMs = DateTime.now().millisecondsSinceEpoch;
    _idleSecondsElapsed = 0;
  }

  void _triggerInactivityDespawn() {
    _despawnAndStopAllTimers();
    if (mounted) {
      setState(() {
        _isDespawnedForInactivity = true;
      });
    }
  }

  void _despawnAndStopAllTimers() {
    _arenaHeartbeatTimer?.cancel();
    _queueRetryTimer?.cancel();
    _raidSubscription?.cancel();
    if (_raidRef != null) {
      _raidRef!.update({'status': 'closed'}).catchError((_) {});
      _raidRef!.delete().catchError((_) {});
      _raidRef = null;
    }
  }

  Future _triggerDefeat() async {
    _currentRaidStatus = 'failed';
    if (_raidRef != null) {
      await _raidRef!.update({'status': 'failed'}).catchError((_) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _despawnAndStopAllTimers();
    } else if (state == AppLifecycleState.resumed && !_isDespawnedForInactivity && !_isNightLockActive) {
      _sendHeartbeatNow();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = DateTime.now();
    if (now.hour >= 0 && now.hour < 6) {
      setState(() {
        _isNightLockActive = true;
        _isAllocating = false;
      });
      return;
    }
    if (_roomId == null && !_isWorldSaturated && !_isNightLockActive && !_isDespawnedForInactivity) {
      _resolveRoomAllocation();
    }
  }

  String _generateRandomToken(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  Future _resolveRoomAllocation() async {
    final now = DateTime.now();
    if (now.hour >= 0 && now.hour < 6) {
      if (mounted) {
        setState(() {
          _isAllocating = false;
          _isNightLockActive = true;
        });
      }
      return;
    }

    _recordActivity();

    final fullUrl = Uri.decodeFull(Uri.base.toString());
    String? explicitRoom;

    final roomRegex = RegExp(r'[?&]room=([a-zA-Z0-9_]+)');
    final match = roomRegex.firstMatch(fullUrl);
    if (match != null) {
      explicitRoom = match.group(1);
    }

    final String myInstanceToken = 'inst_${_generateRandomToken(12)}';
    String? chosenRoom;

    if (explicitRoom != null && explicitRoom.trim().isNotEmpty) {
      chosenRoom = explicitRoom.trim();
    } else {
      chosenRoom = await _claimNextAvailableRoomSlot(myInstanceToken);
    }

    if (!mounted) return;

    if (chosenRoom == null) {
      setState(() {
        _isAllocating = false;
        _isWorldSaturated = true;
      });

      _queueRetryTimer?.cancel();
      _queueRetryTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            _isAllocating = true;
            _isWorldSaturated = false;
          });
          _resolveRoomAllocation();
        }
      });
      return;
    }

    _queueRetryTimer?.cancel();

    final ref = FirebaseFirestore.instance.collection('current_raids').doc(chosenRoom);
    final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final existingDoc = await ref.get();
      String keyToUse = _generateRandomToken(6);
      String tokenToUse = _generateRandomToken(8);

      if (!existingDoc.exists) {
        final Map<String, dynamic> roomData = {
          'roomId': chosenRoom,
          'boss_name': 'MONARQUE DU FEU',
          'instance_token': myInstanceToken,
          'join_token': tokenToUse,
          'admin_key': keyToUse,
          'status': 'waiting',
          'preset_label': 'RAID STANDARD (5 000 PV)',
          'current_hp': 5000,
          'max_hp': 5000,
          'hunters': [],
          'logs': [],
          'target_end_time': midnight.millisecondsSinceEpoch,
          'arena_last_seen': DateTime.now().millisecondsSinceEpoch,
        };
        await ref.set(roomData);
      } else {
        final Map data = existingDoc.data() ?? {};
        final int lastSeen = (data['arena_last_seen'] as num?)?.toInt() ?? 0;
        final bool isStale = lastSeen == 0 || (now.millisecondsSinceEpoch - lastSeen > kRoomDeathThresholdMs);

        if (!isStale) {
          final String existingKey = (data['admin_key'] ?? '').toString().trim();
          final String existingToken = (data['join_token'] ?? '').toString().trim();
          if (existingKey.isNotEmpty) keyToUse = existingKey;
          if (existingToken.isNotEmpty) tokenToUse = existingToken;
        }

        final Map<String, dynamic> updateData = {
          'roomId': chosenRoom,
          'boss_name': 'MONARQUE DU FEU',
          'instance_token': myInstanceToken,
          'join_token': tokenToUse,
          'admin_key': keyToUse,
          'status': isStale ? 'waiting' : (data['status'] ?? 'waiting'),
          'preset_label': 'RAID STANDARD (5 000 PV)',
          'current_hp': isStale ? 5000 : (data['current_hp'] ?? 5000),
          'max_hp': 5000,
          'hunters': isStale ? [] : (data['hunters'] ?? []),
          'logs': isStale ? [] : (data['logs'] ?? []),
          'target_end_time': isStale ? midnight.millisecondsSinceEpoch : (data['target_end_time'] ?? midnight.millisecondsSinceEpoch),
          'arena_last_seen': DateTime.now().millisecondsSinceEpoch,
        };

        await ref.set(updateData, SetOptions(merge: true));
      }

      if (!mounted) return;

      _recordActivity();

      setState(() {
        _roomId = chosenRoom;
        _instanceToken = myInstanceToken;
        _adminKey = keyToUse;
        _joinToken = tokenToUse;
        _raidRef = ref;
        _isAllocating = false;
        _isWorldSaturated = false;
        _isDespawnedForInactivity = false;
      });

      _startArenaHeartbeat();
      _startListeningToRaid();
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('resource-exhausted') || e.toString().contains('quota')) {
        setState(() {
          _isAllocating = false;
          _isNightLockActive = true;
        });
      } else {
        // En cas d'erreur réseau temporaire, on réessaie proprement après 5 secondes
        _queueRetryTimer?.cancel();
        _queueRetryTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _resolveRoomAllocation();
        });
      }
    }
  }

  void _startListeningToRaid() {
    _raidSubscription?.cancel();
    if (_raidRef == null) return;

    _raidSubscription = _raidRef!.snapshots().listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final Map mapData = Map.from(doc.data() as Map? ?? {});
        final double hp = ((mapData['current_hp'] ?? 5000) as num).toDouble();
        final String st = (mapData['status'] ?? 'waiting').toString();
        final dynamic rawHunters = mapData['hunters'];
        final int hunterCount = rawHunters is Iterable ? rawHunters.length : 0;

        if (hunterCount != _lastKnownHunterCount || hp != _lastKnownHp || st != _lastKnownStatus) {
          _recordActivity();
          _lastKnownHunterCount = hunterCount;
          _lastKnownHp = hp;
          _lastKnownStatus = st;
        }

        if (hp <= 0 && st == 'active') {
          _raidRef!.update({'status': 'victory', 'current_hp': 0}).catchError((_) {});
          mapData['status'] = 'victory';
          mapData['current_hp'] = 0;
        }

        _cleanInactiveHuntersIfNeeded(mapData);

        setState(() {
          _raidData = mapData;
          _isRaidDataLoaded = true;
        });
      } else {
        setState(() {
          _raidData = {};
          _isRaidDataLoaded = true;
        });
      }
    }, onError: (e) {
      if (e.toString().contains('resource-exhausted') && mounted) {
        setState(() {
          _isNightLockActive = true;
        });
      }
    });
  }

  void _cleanInactiveHuntersIfNeeded(Map mapData) {
    if (_raidRef == null) return;
    final dynamic rawHunters = mapData['hunters'];
    if (rawHunters is! Iterable || rawHunters.isEmpty) return;

    final List currentHunters = List.from(rawHunters);
    final int now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;

    currentHunters.removeWhere((h) {
      if (h is Map && h.containsKey('last_seen')) {
        final int lastSeen = (h['last_seen'] as num).toInt();
        final int totalDmg = (h['total_damage'] as num?)?.toInt() ?? 0;
        if (now - lastSeen > 60000 && totalDmg == 0) {
          changed = true;
          return true;
        }
      }
      return false;
    });

    if (changed) {
      _raidRef!.update({'hunters': currentHunters}).catchError((_) {});
    }
  }

  Future<String?> _claimNextAvailableRoomSlot(String instanceToken) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day, 23, 59, 59);

    try {
      final snapshot = await firestore.collection('current_raids').get();
      final Map occupiedNumbers = {};

      for (var doc in snapshot.docs) {
        if (doc.id.startsWith('room_')) {
          final numPart = int.tryParse(doc.id.replaceFirst('room_', ''));
          if (numPart != null) {
            final Map data = doc.data();
            final int lastSeen = (data['arena_last_seen'] as num?)?.toInt() ?? 0;

            if (lastSeen == 0 || (now - lastSeen > kRoomDeathThresholdMs)) {
              await doc.reference.delete().catchError((_) {});
            } else {
              occupiedNumbers[numPart] = true;
            }
          }
        }
      }

      int candidate = 1;
      while (occupiedNumbers[candidate] == true) {
        candidate++;
      }

      if (candidate > kMaxGlobalRooms) {
        return null;
      }

      final allocatedRoom = 'room_$candidate';
      final newKey = _generateRandomToken(6);
      final newToken = _generateRandomToken(8);

      // STRUCTURE COMPLÈTE DÈS LA CRÉATION POUR RESPECTER FIRESTORE.RULES
      await firestore.collection('current_raids').doc(allocatedRoom).set({
        'roomId': allocatedRoom,
        'boss_name': 'MONARQUE DU FEU',
        'instance_token': instanceToken,
        'join_token': newToken,
        'admin_key': newKey,
        'status': 'waiting',
        'preset_label': 'RAID STANDARD (5 000 PV)',
        'current_hp': 5000,
        'max_hp': 5000,
        'hunters': [],
        'logs': [],
        'target_end_time': midnight.millisecondsSinceEpoch,
        'arena_last_seen': now,
      }, SetOptions(merge: true));

      return allocatedRoom;
    } catch (e) {
      debugPrint("Erreur allocation slot: $e");
      return 'room_1';
    }
  }

  void _sendHeartbeatNow() {
    if (_raidRef != null && !_isDespawnedForInactivity && !_isNightLockActive) {
      _raidRef!.update({
        'arena_last_seen': DateTime.now().millisecondsSinceEpoch,
      }).catchError((_) {});
    }
  }

  void _startArenaHeartbeat() {
    _arenaHeartbeatTimer?.cancel();
    _arenaHeartbeatTimer = Timer.periodic(const Duration(seconds: kHeartbeatIntervalSeconds), (_) {
      _sendHeartbeatNow();
    });
  }

  void _syncTargetTime(dynamic cloudTime) {
    int incomingMs = 0;
    if (cloudTime is int) {
      incomingMs = cloudTime;
    } else if (cloudTime is Timestamp) {
      incomingMs = cloudTime.millisecondsSinceEpoch;
    }

    if (incomingMs > 0 && (incomingMs - _targetEndTimeMs).abs() > 1000) {
      _targetEndTimeMs = incomingMs;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final diff = (_targetEndTimeMs - nowMs) ~/ 1000;
      _remainingSeconds = diff > 0 ? diff : 0;
    }
  }

  String _formatTimer(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localTickTimer?.cancel();
    _despawnAndStopAllTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isNightLockActive) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF04101E),
              border: Border.all(color: const Color(0xFFFF2E56), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lock_clock, color: Color(0xFFFF2E56), size: 64),
                SizedBox(height: 20),
                Text(
                  "[ SYSTÈME : PORTAILS SCELLÉS (00H00 - 06H00) ]",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFF2E56),
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  "Le quota d'énergie du Donjon est en repos nocturne.\n"
                  "Reposez votre Hardware. Réouverture automatique à 6h00 du matin.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isDespawnedForInactivity) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF04101E),
              border: Border.all(color: const Color(0xFF00E5FF), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.snooze, color: Color(0xFF00E5FF), size: 64),
                const SizedBox(height: 20),
                const Text(
                  "PORTAIL MIS EN VEILLE (60S D'INACTIVITÉ)",
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Aucune activité physique détectée pendant 60 secondes.\n"
                  "La salle a été automatiquement purgée du serveur pour libérer le slot mondial.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () {
                    setState(() {
                      _roomId = null;
                      _isDespawnedForInactivity = false;
                      _isAllocating = true;
                    });
                    _resolveRoomAllocation();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    "RÉOUVRIR UNE SALLE DE RAID",
                    style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isWorldSaturated) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF04101E),
              border: Border.all(color: const Color(0xFFFF9100), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(color: Color(0xFFFF9100), strokeWidth: 3),
                SizedBox(height: 24),
                Text(
                  "PORTAILS MONDIAUX SATURÉS",
                  style: TextStyle(
                    color: Color(0xFFFF9100),
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  "Les 100 failles dimensionnelles sont actuellement engagées en combat.\n"
                  "En attente de libération d'un slot... (Nouvelle tentative dans 10 secondes)",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isAllocating || _raidRef == null || !_isRaidDataLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070D),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00E5FF)),
              SizedBox(height: 16),
              Text(
                "VERROUILLAGE DU PORTAIL...",
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isRaidDataLoaded && _raidData.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF04101E),
              border: Border.all(color: const Color(0xFFFF2E56), width: 2),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.portable_wifi_off, color: Color(0xFFFF2E56), size: 54),
                SizedBox(height: 16),
                Text(
                  "LE PORTAIL S'EST REFERMÉ",
                  style: TextStyle(
                    color: Color(0xFFFF2E56),
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Map data = _raidData;
    final String status = (data['status'] ?? 'waiting').toString();
    final String presetLabel = (data['preset_label'] ?? 'RAID STANDARD (5 000 PV)').toString();
    final double maxHp = 5000.0;
    final double currentHp = ((data['current_hp'] ?? 5000) as num).toDouble().clamp(0.0, 5000.0);
    final dynamic rawHunters = data['hunters'];
    final List hunters = rawHunters is Iterable ? rawHunters.toList() : [];
    final dynamic rawLogs = data['logs'];
    final List logs = rawLogs is Iterable ? rawLogs.toList() : [];

    final String dbJoinToken = (data['join_token'] ?? '').toString().trim();
    final String dbAdminKey = (data['admin_key'] ?? '').toString().trim();
    if (dbJoinToken.isNotEmpty && dbJoinToken != _joinToken) _joinToken = dbJoinToken;
    if (dbAdminKey.isNotEmpty && dbAdminKey != _adminKey) _adminKey = dbAdminKey;

    _currentRaidStatus = status;
    _currentBossHp = currentHp;

    if (data.containsKey('target_end_time')) {
      _syncTargetTime(data['target_end_time']);
    }

    final bool isDefeat = (status == 'failed') ||
        (_remainingSeconds == 0 && (status == 'active' || status == 'failed') && currentHp > 0);
    final bool isVictory = (status == 'victory') || (currentHp <= 0);

    Widget innerContent;
    if (isVictory) {
      innerContent = _buildCompleteMultiWayPodium(logs, hunters);
    } else if (isDefeat) {
      innerContent = _buildDefeatScreen(currentHp, maxHp, logs, hunters);
    } else {
      innerContent = status == 'waiting'
          ? _buildWaitingLobby(hunters)
          : _buildCombatWithMiniPodiumPanel(logs, hunters);
    }

    Widget mainContent = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: innerContent,
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: _buildRightSideDoubleQrPanel(status),
        ),
      ],
    );

    final int sleepCountdown = (kMaxInactivitySeconds - _idleSecondsElapsed).clamp(0, kMaxInactivitySeconds);

    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (_remainingSeconds > 0 && _remainingSeconds <= 600 && !isVictory && !isDefeat)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2E56).withOpacity(0.2),
                    border: Border.all(color: const Color(0xFFFF2E56)),
                  ),
                  child: const Text(
                    "⚠ ALERTE : LE DONJON MONDIAL SE REFERME À MINUIT. FIN DE LA PÉRIODE D'ASSAUT IMMINENTE.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFF2E56),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              _buildTopHeader(currentHp, maxHp, isVictory, isDefeat, presetLabel, sleepCountdown),
              const SizedBox(height: 16),
              Expanded(child: mainContent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(double currentHp, double maxHp, bool isVictory, bool isDefeat, String presetLabel, int sleepCountdown) {
    final double safeMax = maxHp > 0 ? maxHp : 5000.0;
    final double hpRatio = (currentHp / safeMax).clamp(0.0, 1.0);

    Color themeColor = const Color(0xFF00E5FF);
    String titleText = 'DONJON QUOTIDIEN [SALLE : $_roomId]';

    if (isVictory) {
      themeColor = const Color(0xFFFFD700);
      titleText = 'SALLE [$_roomId] : MONARQUE DU FEU TERRASSÉ';
    } else if (isDefeat) {
      themeColor = const Color(0xFFFF2E56);
      titleText = 'SALLE [$_roomId] : ÉCHEC DU DONJON (TEMPS ÉCOULÉ)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: themeColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: TextStyle(
                        color: themeColor,
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "CONFIGURATION : $presetLabel (BOSS: ${currentHp.toInt()} / ${safeMax.toInt()} PV) | VEILLE AUTO : ${sleepCountdown}s",
                      style: const TextStyle(
                        color: Color(0xFFFF9100),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'RÉINITIALISATION : ${_formatTimer(_remainingSeconds)}',
                style: TextStyle(
                  color: isDefeat || (_remainingSeconds <= 60 && !isVictory)
                      ? const Color(0xFFFF2E56)
                      : Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: isDefeat ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: 24,
                    color: Colors.black45,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    width: constraints.maxWidth * hpRatio,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2E56),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2E56).withOpacity(0.8),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDefeatScreen(double currentHp, double maxHp, List logs, List hunters) {
    int totalInflicted = 0;

    for (final h in hunters) {
      if (h is Map) {
        totalInflicted += (h['total_damage'] as num?)?.toInt() ?? 0;
      }
    }

    if (totalInflicted == 0) {
      for (final l in logs) {
        if (l is Map) {
          totalInflicted += (l['damage'] as num?)?.toInt() ?? 0;
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFF2E56), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dangerous_outlined, color: Color(0xFFFF2E56), size: 72),
          const SizedBox(height: 12),
          const Text(
            "☠ ÉCHEC DU RAID : LE PORTAIL S'EST REFERMÉ ☠",
            style: TextStyle(
              color: Color(0xFFFF2E56),
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Le temps imparti est écoulé. Le Monarque du Feu a survécu à votre assaut.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDefeatStatBox("DÉGÂTS INFLIGÉS", "$totalInflicted PV", const Color(0xFF00E5FF)),
              const SizedBox(width: 16),
              _buildDefeatStatBox("PV RESTANTS DU BOSS", "${currentHp.toInt()} PV", const Color(0xFFFF2E56)),
              const SizedBox(width: 16),
              _buildDefeatStatBox("CHASSEURS ENGAGÉS", "${hunters.length}", const Color(0xFFFF9100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDefeatStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black45,
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCombatWithMiniPodiumPanel(List logList, List hunterList) {
    final Map damageByHunter = {};
    for (final h in hunterList) {
      if (h is Map) {
        final String name = (h['name'] ?? 'Chasseur').toString();
        final int dmg = (h['total_damage'] as num?)?.toInt() ?? 0;
        if (dmg > 0) {
          damageByHunter[name] = ((damageByHunter[name] as int?) ?? 0) + dmg;
        }
      }
    }

    if (damageByHunter.isEmpty) {
      for (final l in logList) {
        if (l is Map) {
          final String name = (l['name'] ?? 'Chasseur').toString();
          final int dmg = (l['damage'] as num?)?.toInt() ?? 0;
          damageByHunter[name] = ((damageByHunter[name] as int?) ?? 0) + dmg;
        }
      }
    }

    final List sortedLiveHunters = damageByHunter.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    final List liveTop3 = sortedLiveHunters.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E).withOpacity(0.8),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black54,
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.6), width: 1.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.leaderboard, color: Color(0xFFFFD700), size: 16),
                    SizedBox(width: 8),
                    Text(
                      "CLASSEMENT PROVISOIRE (TOP 3 EN DIRECT)",
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (liveTop3.isEmpty)
                  const Text(
                    "En attente des premières frappes...",
                    style: TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace'),
                  )
                else
                  Row(
                    children: List.generate(liveTop3.length, (idx) {
                      final item = liveTop3[idx];
                      final Color medalColor = idx == 0
                          ? const Color(0xFFFFD700)
                          : (idx == 1 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32));
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: idx < liveTop3.length - 1 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: medalColor.withOpacity(0.08),
                            border: Border.all(color: medalColor.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                "#${idx + 1}",
                                style: TextStyle(
                                  color: medalColor,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.key.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                "${item.value} PV",
                                style: TextStyle(
                                  color: medalColor,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REGISTRE DES ASSAUTS',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'DERNIÈRE FRAPPE EN HAUT ↑',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: logList.isEmpty
                ? const Center(
                    child: Text(
                      'COMBAT COMMENCÉ : EN ATTENTE DU PREMIER ASSAUT',
                      style: TextStyle(color: Colors.white38, fontFamily: 'monospace'),
                    ),
                  )
                : ListView.builder(
                    itemCount: logList.length,
                    itemBuilder: (context, index) {
                      final Map log = logList[index] is Map ? logList[index] : {};
                      final String name = (log['name'] ?? 'Chasseur').toString();
                      final String action = (log['action'] ?? 'Frappe').toString();
                      final int damage = (log['damage'] as num?)?.toInt() ?? 0;

                      final bool isGlow = (damage >= 150);

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isGlow ? const Color(0xFFFF2E56).withOpacity(0.18) : Colors.transparent,
                          border: Border.all(
                            color: isGlow ? const Color(0xFFFF2E56) : Colors.white10,
                            width: isGlow ? 1.8 : 0.8,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: isGlow
                              ? [BoxShadow(color: const Color(0xFFFF2E56).withOpacity(0.45), blurRadius: 10)]
                              : [],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isGlow ? Icons.whatshot : Icons.flash_on,
                              color: isGlow ? const Color(0xFFFF2E56) : const Color(0xFF00E5FF),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isGlow ? const Color(0xFFFFD700) : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      shadows: isGlow
                                          ? [const Shadow(color: Color(0xFFFF9100), blurRadius: 10)]
                                          : [],
                                    ),
                                  ),
                                  if (isGlow) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF2E56),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        damage >= 200 ? "BURST ULTIME" : "FRÉNÉSIE",
                                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                                  Text(
                                    ': $action',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '-$damage PV',
                              style: TextStyle(
                                color: isGlow ? const Color(0xFFFF2E56) : const Color(0xFFFF9100),
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                fontSize: isGlow ? 15 : 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteMultiWayPodium(List logs, List hunters) {
    final Map hunterChosenMode = {};
    final Map totalDmg = {};
    final Map squatReps = {};
    final Map pushupReps = {};
    final Map absReps = {};

    int globalSquats = 0;
    int globalPushups = 0;
    int globalAbs = 0;

    bool hasHunterCumulativeStats = false;

    for (final h in hunters) {
      if (h is Map) {
        final String name = (h['name'] ?? 'Chasseur').toString();
        final String modeId = (h['mode_id'] ?? 'all').toString();
        hunterChosenMode[name] = modeId;

        final int hDmg = (h['total_damage'] as num?)?.toInt() ?? 0;
        final int hSq = (h['squat_reps'] as num?)?.toInt() ?? 0;
        final int hPu = (h['pushup_reps'] as num?)?.toInt() ?? 0;
        final int hAb = (h['abs_reps'] as num?)?.toInt() ?? 0;

        if (hDmg > 0 || hSq > 0 || hPu > 0 || hAb > 0) {
          hasHunterCumulativeStats = true;
          totalDmg[name] = ((totalDmg[name] as int?) ?? 0) + hDmg;
          squatReps[name] = ((squatReps[name] as int?) ?? 0) + hSq;
          pushupReps[name] = ((pushupReps[name] as int?) ?? 0) + hPu;
          absReps[name] = ((absReps[name] as int?) ?? 0) + hAb;

          globalSquats += hSq;
          globalPushups += hPu;
          globalAbs += hAb;
        }
      }
    }

    if (!hasHunterCumulativeStats) {
      for (final l in logs) {
        if (l is Map) {
          final String name = (l['name'] ?? 'Chasseur').toString();
          final int dmg = (l['damage'] as num?)?.toInt() ?? 0;
          final String cat = (l['category'] ?? '').toString();
          final int reps = (l['reps'] as num?)?.toInt() ?? 0;
          final int count = reps > 0 ? reps : 5;

          totalDmg[name] = ((totalDmg[name] as int?) ?? 0) + dmg;

          if (cat == 'squat') {
            squatReps[name] = ((squatReps[name] as int?) ?? 0) + count;
            globalSquats += count;
          } else if (cat == 'pushup') {
            pushupReps[name] = ((pushupReps[name] as int?) ?? 0) + count;
            globalPushups += count;
          } else if (cat == 'abs') {
            absReps[name] = ((absReps[name] as int?) ?? 0) + count;
            globalAbs += count;
          }
        }
      }
    }

    final int grandTotalReps = globalSquats + globalPushups + globalAbs;
    String dominantZoneText = "AUCUNE ZONE DOMINANTE";
    Color dominantColor = const Color(0xFFFFD700);

    if (grandTotalReps > 0) {
      if (globalSquats >= globalPushups && globalSquats >= globalAbs) {
        final pct = ((globalSquats / grandTotalReps) * 100).toStringAsFixed(1);
        dominantZoneText = "DISCIPLINE DOMINANTE : VOIE DES JAMBES (SQUATS) — $globalSquats REPS ($pct% DE L'EFFORT)";
        dominantColor = const Color(0xFF00E5FF);
      } else if (globalPushups >= globalSquats && globalPushups >= globalAbs) {
        final pct = ((globalPushups / grandTotalReps) * 100).toStringAsFixed(1);
        dominantZoneText = "DISCIPLINE DOMINANTE : VOIE DU HAUT (POMPES) — $globalPushups REPS ($pct% DE L'EFFORT)";
        dominantColor = const Color(0xFFFF9100);
      } else {
        final pct = ((globalAbs / grandTotalReps) * 100).toStringAsFixed(1);
        dominantZoneText = "DISCIPLINE DOMINANTE : VOIE DU TRONC (ABDOS) — $globalAbs REPS ($pct% DE L'EFFORT)";
        dominantColor = const Color(0xFF00FF66);
      }
    }

    final List sortedOverall = totalDmg.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    final List top10Overall = sortedOverall.take(10).toList();

    final Map rankingMonarque = {};
    final Map rankingSquats = {};
    final Map rankingPushups = {};
    final Map rankingAbs = {};
    final Map rankingForceBrute = {};
    final Map rankingJambesTronc = {};
    final Map rankingHautTronc = {};

    totalDmg.forEach((hunterName, dmg) {
      final String modeId = (hunterChosenMode[hunterName] ?? 'all').toString();
      final int sReps = (squatReps[hunterName] as int?) ?? 0;
      final int pReps = (pushupReps[hunterName] as int?) ?? 0;
      final int aReps = (absReps[hunterName] as int?) ?? 0;

      final Map payload = {
        'damage': dmg,
        'squat_reps': sReps,
        'pushup_reps': pReps,
        'abs_reps': aReps,
      };

      switch (modeId) {
        case 'squats_only':
          rankingSquats[hunterName] = payload;
          break;
        case 'pushups_only':
          rankingPushups[hunterName] = payload;
          break;
        case 'abs_only':
          rankingAbs[hunterName] = payload;
          break;
        case 'squats_pushups':
          rankingForceBrute[hunterName] = payload;
          break;
        case 'squats_abs':
          rankingJambesTronc[hunterName] = payload;
          break;
        case 'pushups_abs':
          rankingHautTronc[hunterName] = payload;
          break;
        case 'all':
        default:
          rankingMonarque[hunterName] = payload;
          break;
      }
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
      ),
      child: Column(
        children: [
          const Text(
            "★ PANTHÉON DU DONJON : VICTOIRE & STATISTIQUES FINALES ★",
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: dominantColor.withOpacity(0.12),
              border: Border.all(color: dominantColor, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    dominantZoneText,
                    style: TextStyle(
                      color: dominantColor,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  "TOTAL : $grandTotalReps REPS IMPACTÉES",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.military_tech, color: Color(0xFFFFD700), size: 16),
                            SizedBox(width: 6),
                            Text(
                              "TOP 10 GÉNÉRAL DU DONJON",
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white12, height: 8),
                        Expanded(
                          child: top10Overall.isEmpty
                              ? const Center(
                                  child: Text("Aucun participant", style: TextStyle(color: Colors.white24, fontSize: 10)),
                                )
                              : ListView.builder(
                                  itemCount: top10Overall.length,
                                  itemBuilder: (ctx, idx) {
                                    final item = top10Overall[idx];
                                    final rankColor = idx == 0
                                        ? const Color(0xFFFFD700)
                                        : (idx == 1
                                            ? const Color(0xFFC0C0C0)
                                            : (idx == 2 ? const Color(0xFFCD7F32) : Colors.white70));
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: rankColor.withOpacity(0.15),
                                              border: Border.all(color: rankColor),
                                            ),
                                            child: Center(
                                              child: Text(
                                                "${idx + 1}",
                                                style: TextStyle(
                                                  color: rankColor,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item.key.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            "${item.value} PV",
                                            style: TextStyle(
                                              color: rankColor,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: _buildPodiumCategoryCard(
                    title: "ENTRAÎNEMENT DU MONARQUE (SQUATS + POMPES + ABDOS)",
                    color: const Color(0xFFFFD700),
                    icon: Icons.emoji_events,
                    rankingMap: rankingMonarque,
                    categoryType: 'monarque',
                    isGlobal: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildPodiumCategoryCard(
                    title: "VOIE DES JAMBES (SQUATS)",
                    color: const Color(0xFF00E5FF),
                    icon: Icons.directions_run,
                    rankingMap: rankingSquats,
                    categoryType: 'squats',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPodiumCategoryCard(
                    title: "VOIE DU HAUT (POMPES)",
                    color: const Color(0xFFFF9100),
                    icon: Icons.fitness_center,
                    rankingMap: rankingPushups,
                    categoryType: 'pushups',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPodiumCategoryCard(
                    title: "VOIE DU TRONC (ABDOS)",
                    color: const Color(0xFF00FF66),
                    icon: Icons.shield,
                    rankingMap: rankingAbs,
                    categoryType: 'abs',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildPodiumCategoryCard(
                    title: "FORCE BRUTE (SQUATS + POMPES)",
                    color: const Color(0xFFFF2E56),
                    icon: Icons.flash_on,
                    rankingMap: rankingForceBrute,
                    categoryType: 'squats_pushups',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPodiumCategoryCard(
                    title: "JAMBES & TRONC (SQUATS + ABDOS)",
                    color: const Color(0xFFB388FF),
                    icon: Icons.hub,
                    rankingMap: rankingJambesTronc,
                    categoryType: 'squats_abs',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPodiumCategoryCard(
                    title: "HAUT & TRONC (POMPES + ABDOS)",
                    color: const Color(0xFF40C4FF),
                    icon: Icons.military_tech,
                    rankingMap: rankingHautTronc,
                    categoryType: 'pushups_abs',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingLobby(List hunterList) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E).withOpacity(0.8),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PORTAIL ACTIF : SALLE [$_roomId]',
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${hunterList.length} / $kMaxHuntersPerRoom CHASSEURS',
                style: TextStyle(
                  color: hunterList.length >= kMaxHuntersPerRoom
                      ? const Color(0xFFFF2E56)
                      : const Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: hunterList.isEmpty
                ? const Center(
                    child: Text(
                      'AUCUN CHASSEUR DÉTECTÉ\nEN ATTENTE DU SCAN... (Mise en veille auto après 60s sans activité)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: hunterList.length,
                    itemBuilder: (context, index) {
                      final Map h = hunterList[index] is Map ? hunterList[index] : {};
                      final String name = (h['name'] ?? 'Chasseur').toString();
                      final String mode = (h['mode_label'] ?? 'Arsenal').toString();

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield, color: Color(0xFF00E5FF), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    mode,
                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            const Text(
                              'PRÊT',
                              style: TextStyle(
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSideDoubleQrPanel(String raidStatus) {
    final String rawJoinUrl = 'https://shadowburn-1d8f8.web.app/#/join?room=$_roomId&token=${_joinToken ?? ""}';
    final joinQrData = Uri.encodeComponent(rawJoinUrl);

    const String apkDownloadUrl = 'https://github.com/Matou7/shadowburn-webhook/releases/latest/download/ShadowBurn.apk';
    final apkQrData = Uri.encodeComponent(apkDownloadUrl);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E).withOpacity(0.8),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- SECTION 1 : SCAN CHASSEUR (REJOINDRE) ---
            const Text(
              'SCAN CHASSEUR',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 9.5,
                letterSpacing: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(2),
              color: Colors.white,
              child: Image.network(
                'https://api.qrserver.com/v1/create-qr-code/?size=80x80&data=$joinQrData',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.qr_code_2,
                  size: 60,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              raidStatus == 'waiting' ? '(En attente)' : '(Actif)',
              style: TextStyle(
                color: raidStatus == 'waiting' ? Colors.white54 : const Color(0xFF00FF66),
                fontSize: 8.5,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 14),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 14),

            // --- SECTION 2 : TÉLÉCOMMANDE MAÎTRE ---
            const Text(
              'TÉLÉCOMMANDE',
              style: TextStyle(
                color: Color(0xFFFF9100),
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 9.5,
                letterSpacing: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(2),
              color: Colors.white,
              child: Image.network(
                'https://api.qrserver.com/v1/create-qr-code/?size=80x80&data=${Uri.encodeComponent('https://shadowburn-1d8f8.web.app/#/admin?room=$_roomId&key=${_adminKey ?? ""}')}',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.admin_panel_settings,
                  size: 60,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Salle : $_roomId',
              style: const TextStyle(
                color: Color(0xFFFF9100),
                fontSize: 8.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 14),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 14),

            // --- SECTION 3 : TÉLÉCHARGER L'APPLICATION APK ---
            const Text(
              'TÉLÉCHARGER APK',
              style: TextStyle(
                color: Color(0xFF00FF66),
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 9.5,
                letterSpacing: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(2),
              color: Colors.white,
              child: Image.network(
                'https://api.qrserver.com/v1/create-qr-code/?size=80x80&data=$apkQrData',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.android,
                  size: 60,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '(Android Mobile)',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 8.5,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodiumCategoryCard({
    required String title,
    required Color color,
    required IconData icon,
    required Map rankingMap,
    required String categoryType,
    bool isGlobal = false,
  }) {
    final List sorted = rankingMap.entries.toList()
      ..sort((a, b) => ((b.value as Map)['damage'] as int).compareTo((a.value as Map)['damage'] as int));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black45,
        border: Border.all(color: color.withOpacity(0.6), width: isGlobal ? 1.5 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: isGlobal ? 16 : 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: isGlobal ? 11 : 9.5,
                    letterSpacing: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 8),
          Expanded(
            child: sorted.isEmpty
                ? const Center(
                    child: Text(
                      "Aucun participant",
                      style: TextStyle(color: Colors.white24, fontSize: 9.5, fontFamily: 'monospace'),
                    ),
                  )
                : ListView.builder(
                    itemCount: sorted.length > 3 ? 3 : sorted.length,
                    itemBuilder: (context, index) {
                      final entry = sorted[index];
                      final String name = entry.key.toString();
                      final Map valMap = entry.value as Map;
                      final int dmg = valMap['damage'] as int;
                      final int sq = valMap['squat_reps'] as int;
                      final int pu = valMap['pushup_reps'] as int;
                      final int ab = valMap['abs_reps'] as int;

                      String detailStr = "-$dmg PV";
                      if (categoryType == 'squats') {
                        detailStr = "[-$dmg PV / $sq reps]";
                      } else if (categoryType == 'pushups') {
                        detailStr = "[-$dmg PV / $pu reps]";
                      } else if (categoryType == 'abs') {
                        detailStr = "[-$dmg PV / $ab reps]";
                      } else if (categoryType == 'squats_pushups') {
                        detailStr = "[-$dmg PV / $sq S, $pu P]";
                      } else if (categoryType == 'squats_abs') {
                        detailStr = "[-$dmg PV / $sq S, $ab A]";
                      } else if (categoryType == 'pushups_abs') {
                        detailStr = "[-$dmg PV / $pu P, $ab A]";
                      } else if (categoryType == 'monarque') {
                        detailStr = "[-$dmg PV / $sq S, $pu P, $ab A]";
                      }

                      final placeColor = index == 0
                          ? const Color(0xFFFFD700)
                          : (index == 1 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32));

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: placeColor.withOpacity(0.2),
                                border: Border.all(color: placeColor),
                              ),
                              child: Center(
                                child: Text(
                                  "${index + 1}",
                                  style: TextStyle(
                                    color: placeColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              detailStr,
                              style: TextStyle(
                                color: color,
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}