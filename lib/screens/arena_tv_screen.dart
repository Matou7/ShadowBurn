// lib/screens/arena_tv_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/audio_service.dart';
import '../services/quota_guard_service.dart';
import 'arena_web_helper_stub.dart' if (dart.library.html) 'arena_web_helper_web.dart';

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
  Timer? _queueRetryTimer;

  Map _raidData = {};
  bool _isRaidDataLoaded = false;

  int _targetEndTimeMs = 0;
  int _remainingSeconds = 0;
  bool _isAllocating = true;
  bool _isWorldSaturated = false;
  bool _isNightLockActive = false;
  bool _isDespawnedForInactivity = false;
  bool _isRadioPlaying = false;

  String _currentRaidStatus = 'waiting';
  double _currentBossHp = 5000.0;

  int _lastRoomActivityMs = 0;
  int _lastKnownHunterCount = 0;
  double _lastKnownHp = 5000.0;
  String _lastKnownStatus = 'waiting';

  static const int kMaxGlobalRooms = 100;
  static const int kMaxHuntersPerRoom = 10;
  static const int kRoomDeathThresholdMs = 45000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastRoomActivityMs = DateTime.now().millisecondsSinceEpoch;

    if (kIsWeb) {
      ArenaWebHelper.registerBeforeUnload(() {
        _despawnAndStopAllTimers();
      });
    }

    _localTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final now = DateTime.now();
      bool isNightClosed = (now.hour >= 0 && now.hour < 6) || (now.hour == 23 && now.minute >= 58);
      if (isNightClosed != _isNightLockActive) {
        setState(() {
          _isNightLockActive = isNightClosed;
        });
        if (isNightClosed) {
          _despawnAndStopAllTimers();
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
  }

  void _despawnAndStopAllTimers() {
    _queueRetryTimer?.cancel();
    _raidSubscription?.cancel();

    if (_isRadioPlaying) {
      _isRadioPlaying = false;
      AudioService.stopNrjStream();
    }

    if (_raidRef != null) {
      _raidRef!.delete().catchError((_) {});
      _raidRef = null;
    }
  }

  Future _triggerDefeat() async {
    _currentRaidStatus = 'failed';
    if (_isRadioPlaying) {
      _isRadioPlaying = false;
      AudioService.stopNrjStream();
    }
    if (_raidRef != null) {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (canWrite) {
        await _raidRef!.update({'status': 'failed'}).catchError((_) {});
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _despawnAndStopAllTimers();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = DateTime.now();
    bool isNightClosed = (now.hour >= 0 && now.hour < 6) || (now.hour == 23 && now.minute >= 58);
    if (isNightClosed) {
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
    bool isNightClosed = (now.hour >= 0 && now.hour < 6) || (now.hour == 23 && now.minute >= 58);
    if (isNightClosed) {
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

    bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
    if (!canWrite) {
      if (mounted) {
        setState(() {
          _isAllocating = false;
          _isNightLockActive = true;
        });
      }
      return;
    }

    final ref = FirebaseFirestore.instance.collection('current_raids').doc(chosenRoom);
    final midnight = DateTime(now.year, now.month, now.day, 23, 58, 0);

    try {
      final existingDoc = await ref.get();
      String keyToUse = _generateRandomToken(6);
      String tokenToUse = _generateRandomToken(8);

      if (!existingDoc.exists) {
        final Map<String, dynamic> roomData = {
          'roomId': chosenRoom,
          'instance_token': myInstanceToken,
          'join_token': tokenToUse,
          'admin_key': keyToUse,
          'status': 'waiting',
          'preset_label': 'RAID STANDARD (5 000 PV)',
          'current_hp': 5000,
          'max_hp': 5000,
          'audio_playing': false,
          'hunters': [],
          'logs': [],
          'target_end_time': midnight.millisecondsSinceEpoch,
          'arena_last_seen': DateTime.now().millisecondsSinceEpoch,
        };
        await ref.set(roomData);
      } else {
        final Map data = existingDoc.data() ?? {};
        final String existingKey = (data['admin_key'] ?? '').toString().trim();
        final String existingToken = (data['join_token'] ?? '').toString().trim();

        if (existingKey.isNotEmpty) keyToUse = existingKey;
        if (existingToken.isNotEmpty) tokenToUse = existingToken;

        final Map<String, dynamic> updateData = {
          'roomId': chosenRoom,
          'instance_token': myInstanceToken,
          'join_token': tokenToUse,
          'admin_key': keyToUse,
          'status': data['status'] ?? 'waiting',
          'preset_label': 'RAID STANDARD (5 000 PV)',
          'current_hp': data['current_hp'] ?? 5000,
          'max_hp': 5000,
          'audio_playing': data.containsKey('audio_playing') ? data['audio_playing'] : false,
          'hunters': data['hunters'] ?? [],
          'logs': data['logs'] ?? [],
          'target_end_time': data['target_end_time'] ?? midnight.millisecondsSinceEpoch,
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

      _startListeningToRaid();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAllocating = false;
        _isNightLockActive = true;
      });
    }
  }

  void _startListeningToRaid() {
    _raidSubscription?.cancel();
    if (_raidRef == null) return;

    _raidSubscription = _raidRef!.snapshots().listen((doc) async {
      if (!mounted) return;
      if (doc.exists) {
        final Map mapData = Map.from(doc.data() as Map? ?? {});
        final double hp = ((mapData['current_hp'] ?? 5000) as num).toDouble();
        final String st = (mapData['status'] ?? 'waiting').toString();
        final dynamic rawHunters = mapData['hunters'];
        final int hunterCount = rawHunters is Iterable ? rawHunters.length : 0;

        final bool remoteAudioPlaying = (mapData['audio_playing'] == true);
        if (remoteAudioPlaying != _isRadioPlaying) {
          _isRadioPlaying = remoteAudioPlaying;
          if (_isRadioPlaying) {
            AudioService.toggleNrjStream();
          } else {
            AudioService.stopNrjStream();
          }
        }

        if (hunterCount != _lastKnownHunterCount || hp != _lastKnownHp || st != _lastKnownStatus) {
          _recordActivity();
          _lastKnownHunterCount = hunterCount;
          _lastKnownHp = hp;
          _lastKnownStatus = st;
        }

        if (hp <= 0 && st == 'active') {
          bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
          if (canWrite) {
            _raidRef!.update({'status': 'victory', 'current_hp': 0}).catchError((_) {});
          }
          mapData['status'] = 'victory';
          mapData['current_hp'] = 0;

          if (_isRadioPlaying) {
            _isRadioPlaying = false;
            AudioService.stopNrjStream();
          }
        }

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

  Future<String?> _claimNextAvailableRoomSlot(String instanceToken) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return null;

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

      await firestore.collection('current_raids').doc(allocatedRoom).set({
        'roomId': allocatedRoom,
        'instance_token': instanceToken,
        'arena_last_seen': now,
      }, SetOptions(merge: true));

      return allocatedRoom;
    } catch (e) {
      debugPrint("Erreur allocation slot: $e");
      return null;
    }
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
                  "[ SYSTÈMES : PORTAILS SCELLÉS (23H58 - 06H00) ]",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFF2E56), fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                SizedBox(height: 12),
                Text(
                  "Le quota d'énergie du Donjon est en repos nocturne.\nReposez votre Hardware. Réouverture automatique à 6h00 du matin.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, height: 1.5),
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
                  style: TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                SizedBox(height: 12),
                Text(
                  "Les 100 failles dimensionnelles sont actuellement engagées en combat.\nEn attente de libération d'un slot... (Nouvelle tentative dans 10 secondes)",
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
                style: TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', letterSpacing: 2),
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
                  style: TextStyle(color: Color(0xFFFF2E56), fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
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

    // En cas de victoire, le podium s'étale sur 100% de la largeur sans le panneau QR latéral
    Widget mainContent = isVictory
        ? innerContent
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: innerContent,
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: _buildDynamicMaximizedQrPanel(status, isVictory: isVictory),
              ),
            ],
          );

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
                    "⚠ ALERTE : LE DONJON MONDIAL SE REFERME À 23H58. FIN DE LA PÉRIODE D'ASSAUT IMMINENTE.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFFF2E56), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
                  ),
                ),
              _buildTopHeader(currentHp, maxHp, isVictory, isDefeat, presetLabel),
              const SizedBox(height: 16),
              Expanded(child: mainContent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(double currentHp, double maxHp, bool isVictory, bool isDefeat, String presetLabel) {
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
                      style: TextStyle(color: themeColor, fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "CONFIGURATION : $presetLabel (BOSS: ${currentHp.toInt()} / ${safeMax.toInt()} PV) | MODE CONVENTION OPTIMISÉ",
                      style: const TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    height: 36,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00E5FF),
                        side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
                        backgroundColor: const Color(0xFF00E5FF).withOpacity(0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () async {
                        bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
                        if (!canWrite) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("[QUOTA] Seuil de sécurité atteint. Écriture bloquée."), backgroundColor: Colors.red),
                            );
                          }
                          return;
                        }

                        bool playing = await AudioService.toggleNrjStream();
                        setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(playing ? "[AUDIO] Lecture en cours..." : "[AUDIO] Musique en pause."),
                              duration: const Duration(milliseconds: 800),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        AudioService.isPlaying ? Icons.pause : Icons.volume_up,
                        size: 16,
                      ),
                      label: Text(
                        AudioService.isPlaying ? "PAUSE AUDIO" : "ACTIVER AUDIO",
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Text(
                    'RÉINITIALISATION : ${_formatTimer(_remainingSeconds)}',
                    style: TextStyle(
                      color: isDefeat || (_remainingSeconds <= 60 && !isVictory) ? const Color(0xFFFF2E56) : Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: isDefeat ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
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
            style: TextStyle(color: Color(0xFFFF2E56), fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
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
                      style: TextStyle(color: Color(0xFFFFD700), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
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
                                style: TextStyle(color: medalColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.key.toString(),
                                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                "${item.value} PV",
                                style: TextStyle(color: medalColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
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
                style: TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                'DERNIÈRE FRAPPE EN HAUT ↑',
                style: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
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

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(color: Colors.white10, width: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flash_on, color: Color(0xFF00E5FF), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                                  ),
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
                              style: const TextStyle(color: Color(0xFFFF9100), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
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
    // Utilisation d'un type Map dynamique sans chevrons complexes pour garantir zéro erreur de parsing
    final Map huntersByMode = {};

    int globalSquats = 0;
    int globalPushups = 0;
    int globalAbs = 0;

    for (final rawH in hunters) {
      if (rawH is Map) {
        final Map<String, dynamic> hunterMap = Map<String, dynamic>.from(rawH);
        final String modeLabel = (hunterMap['mode_label'] ?? 'Entraînement du Monarque').toString();

        huntersByMode.putIfAbsent(modeLabel, () => []);
        huntersByMode[modeLabel]!.add(hunterMap);

        globalSquats += (hunterMap['squat_reps'] as num?)?.toInt() ?? 0;
        globalPushups += (hunterMap['pushup_reps'] as num?)?.toInt() ?? 0;
        globalAbs += (hunterMap['abs_reps'] as num?)?.toInt() ?? 0;
      }
    }

    final int grandTotalReps = globalSquats + globalPushups + globalAbs;
    String dominantZoneText = "AUCUNE ZONE DOMINANTE";
    Color dominantColor = const Color(0xFFFFD700);

    if (grandTotalReps > 0) {
      if (globalSquats >= globalPushups && globalSquats >= globalAbs) {
        final pct = ((globalSquats / grandTotalReps) * 100).toStringAsFixed(1);
        dominantZoneText = "DISCIPLINE DOMINANTE : VOIE DES JAMBES (SQUATS) — $globalSquats REPS ($pct%)";
        dominantColor = const Color(0xFF00E5FF);
      } else if (globalPushups >= globalSquats && globalPushups >= globalAbs) {
        final pct = ((globalPushups / grandTotalReps) * 100).toStringAsFixed(1);
        dominantZoneText = "DISCIPLINE DOMINANTE : VOIE DU HAUT (POMPES) — $globalPushups REPS ($pct%)";
        dominantColor = const Color(0xFFFF9100);
      } else {
        final pct = ((globalAbs / grandTotalReps) * 100).toStringAsFixed(1);
        dominantZoneText = "DISCIPLINE DOMINANTE : VOIE DU TRONC (ABDOS) — $globalAbs REPS ($pct%)";
        dominantColor = const Color(0xFF00FF66);
      }
    }

    final List entries = huntersByMode.entries.toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              "★ PANTHÉON DU DONJON : VICTOIRE & PODIUMS PAR VOIES D'ENTRAÎNEMENT ★",
              style: TextStyle(color: Color(0xFFFFD700), fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    style: TextStyle(color: dominantColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  "TOTAL GLOBAL : $grandTotalReps REPS (Squats: $globalSquats | Pompes: $globalPushups | Abdos: $globalAbs)",
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text("Aucun participant enregistré dans les voies.", style: TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 13)),
                  )
                : ListView(
                    children: entries.map((entry) {
                      final String modeName = entry.key.toString();
                      final List rawList = entry.value is List ? entry.value : [];
                      final List modeHunters = rawList.map((e) => Map<String, dynamic>.from(e)).toList();

                      modeHunters.sort((a, b) {
                        final dmgA = (a['total_damage'] as num?)?.toInt() ?? 0;
                        final dmgB = (b['total_damage'] as num?)?.toInt() ?? 0;
                        return dmgB.compareTo(dmgA);
                      });

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.fitness_center, color: Color(0xFF00E5FF), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  "VOIE : ${modeName.toUpperCase()}",
                                  style: const TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 10),
                            ...List.generate(modeHunters.length, (idx) {
                              final h = modeHunters[idx];
                              final String name = (h['name'] ?? 'Chasseur').toString();
                              final int dmg = (h['total_damage'] as num?)?.toInt() ?? 0;
                              final int sq = (h['squat_reps'] as num?)?.toInt() ?? 0;
                              final int pu = (h['pushup_reps'] as num?)?.toInt() ?? 0;
                              final int ab = (h['abs_reps'] as num?)?.toInt() ?? 0;

                              final Color rankColor = idx == 0
                                  ? const Color(0xFFFFD700)
                                  : (idx == 1 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32));

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: rankColor.withOpacity(0.15),
                                        border: Border.all(color: rankColor),
                                      ),
                                      child: Center(
                                        child: Text(
                                          "#${idx + 1}",
                                          style: TextStyle(color: rankColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name.toUpperCase(),
                                            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            "Squats: $sq | Pompes: $pu | Abdos: $ab",
                                            style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      "$dmg PV",
                                      style: TextStyle(color: rankColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
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
                style: const TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${hunterList.length} / $kMaxHuntersPerRoom CHASSEURS',
                style: TextStyle(
                  color: hunterList.length >= kMaxHuntersPerRoom ? const Color(0xFFFF2E56) : const Color(0xFF00FF66),
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
                      'AUCUN CHASSEUR DÉTECTÉ\nEN ATTENTE DU SCAN... (Mode Convention : Portail permanent)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 13, letterSpacing: 1.2),
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
                                  Text(name, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                  Text(mode, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                ],
                              ),
                            ),
                            const Text(
                              'PRÊT',
                              style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
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

  Widget _buildDynamicMaximizedQrPanel(String raidStatus, {required bool isVictory}) {
    final String rawJoinUrl = 'https://shadowburn-1d8f8.web.app/#/join?room=$_roomId&token=${_joinToken ?? ""}';
    final joinQrData = Uri.encodeComponent(rawJoinUrl);

    final String rawAdminUrl = 'https://shadowburn-1d8f8.web.app/#/admin?room=$_roomId&key=${_adminKey ?? ""}';
    final adminQrData = Uri.encodeComponent(rawAdminUrl);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E).withOpacity(0.9),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6), width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalHeight = constraints.maxHeight;
          final double sectionHeight = (totalHeight - 20) / 2;

          return Column(
            children: [
              SizedBox(
                height: sectionHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'SCAN CHASSEUR',
                      style: TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Image.network(
                              'https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=$joinQrData',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.qr_code_2, size: 80, color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      raidStatus == 'waiting' ? '(En attente)' : '(Actif)',
                      style: TextStyle(color: raidStatus == 'waiting' ? Colors.white54 : const Color(0xFF00FF66), fontSize: 10, fontFamily: 'monospace'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Divider(color: Colors.white24, height: 1),
              ),
              SizedBox(
                height: sectionHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'TÉLÉCOMMANDE',
                      style: TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Image.network(
                              'https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=$adminQrData',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.admin_panel_settings, size: 80, color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Salle : $_roomId',
                      style: const TextStyle(color: Color(0xFFFF9100), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}