// lib/screens/arena_tv_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/audio_service.dart';
import '../services/quota_guard_service.dart';
import '../services/lan_socket_service.dart';
import 'arena_web_helper_stub.dart' if (dart.library.html) 'arena_web_helper_web.dart';

class ArenaTvScreen extends StatefulWidget {
  const ArenaTvScreen({super.key});

  @override
  State<ArenaTvScreen> createState() => _ArenaTvScreenState();
}

class _ArenaTvScreenState extends State<ArenaTvScreen>
    with WidgetsBindingObserver {
  String? _roomId;
  String? _adminKey;
  String? _joinToken;
  DocumentReference? _raidRef;
  StreamSubscription? _raidSubscription;

  bool _isLanMode = false;
  String _lanWsUrl = '';
  final LanSocketService _lanSocket = LanSocketService();
  StreamSubscription? _lanSub;

  Timer? _localTickTimer;
  Timer? _queueRetryTimer;

  Map _raidData = {};
  bool _isRaidDataLoaded = false;

  int _targetEndTimeMs = 0;
  int _remainingSeconds = 0;
  bool _isAllocating = true;
  bool _isWorldSaturated = false;
  bool _isNightLockActive = false;
  bool _isQuotaExhausted = false;
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
  static const int kRoomInactivityThresholdMs = 600000;
  static const Duration _kFirestoreTimeout = Duration(seconds: 6);

  String _resolveDefaultLanWsUrl() {
    final String host =
        Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
    return 'ws://$host:8765';
  }

  Map<String, String> _readUrlParams() {
    String raw = Uri.base.toString();
    try {
      raw = Uri.decodeFull(raw);
    } catch (_) {}

    final Map<String, String> out =
        Map<String, String>.from(Uri.base.queryParameters);
    if (raw.contains('#') && raw.split('#').last.contains('?')) {
      try {
        final fragQuery = raw.split('#').last.split('?').last;
        out.addAll(Uri.splitQueryString(fragQuery));
      } catch (_) {}
    }

    final lower = raw.toLowerCase();
    if ((lower.contains('mode=lan') || lower.contains('ws=')) &&
        !out.containsKey('mode')) {
      out['mode'] = 'lan';
    }
    if (!out.containsKey('ws')) {
      final wsMatch = RegExp(r'(?:^|[?&#])ws=([^&#]+)').firstMatch(raw);
      if (wsMatch != null) {
        out['ws'] = Uri.decodeComponent(wsMatch.group(1)!);
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastRoomActivityMs = DateTime.now().millisecondsSinceEpoch;
    _lanWsUrl = _resolveDefaultLanWsUrl();

    if (kIsWeb) {
      ArenaWebHelper.registerBeforeUnload(() {
        _markDormantAndStopAllTimers();
      });
    }

    _localTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_isLanMode) {
        if (_targetEndTimeMs > 0 &&
            _currentRaidStatus == 'active' &&
            _currentBossHp > 0) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final diff = (_targetEndTimeMs - nowMs) ~/ 1000;
          final remaining = diff > 0 ? diff : 0;
          setState(() {
            _remainingSeconds = remaining;
            if (remaining == 0) {
              _currentRaidStatus = 'failed';
              _raidData['status'] = 'failed';
            }
          });
        }
        return;
      }

      final now = DateTime.now();
      bool isNightClosed =
          (now.hour >= 0 && now.hour < 6) || (now.hour == 23 && now.minute >= 58);
      if (isNightClosed != _isNightLockActive) {
        setState(() {
          _isNightLockActive = isNightClosed;
        });
        if (isNightClosed) {
          _markDormantAndStopAllTimers();
          return;
        }
      }

      if (_targetEndTimeMs > 0 &&
          !_isDespawnedForInactivity &&
          !_isNightLockActive &&
          !_isQuotaExhausted) {
        final nowMs = now.millisecondsSinceEpoch;
        final diff = (_targetEndTimeMs - nowMs) ~/ 1000;
        final remaining = diff > 0 ? diff : 0;

        setState(() {
          _remainingSeconds = remaining;
        });

        if (remaining == 0 &&
            _currentRaidStatus == 'active' &&
            _currentBossHp > 0) {
          _triggerDefeat();
        }
      }
    });
  }

  Future<void> _connectLanTv(String roomId, String wsUrl) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _isLanMode = true;
      _lanWsUrl = wsUrl;
      _roomId = roomId;
      _targetEndTimeMs = nowMs + 1800000;
      _remainingSeconds = 1800;
      _raidData = {
        'roomId': roomId,
        'status': 'waiting',
        'preset_label': 'RAID LAN (5 000 PV)',
        'current_hp': 5000,
        'max_hp': 5000,
        'audio_playing': false,
        'hunters': [],
        'logs': [],
        'target_end_time': nowMs + 1800000,
      };
      _isRaidDataLoaded = true;
      _isAllocating = false;
      _isWorldSaturated = false;
      _isNightLockActive = false;
      _isQuotaExhausted = false;
    });

    await _lanSub?.cancel();
    _lanSub = _lanSocket.messages.listen((msg) {
      if (!mounted) return;
      final String msgType = (msg['type'] ?? '').toString();
      if (msgType == 'state' ||
          msgType == 'welcome' ||
          msgType == 'state_sync') {
        final Map<String, dynamic> incoming = (msg['state'] is Map)
            ? Map<String, dynamic>.from(msg['state'] as Map)
            : Map<String, dynamic>.from(msg);
        final int endMs = (incoming['target_end_time_ms'] as num?)?.toInt() ??
            (incoming['target_end_time'] as num?)?.toInt() ??
            0;
        final int remSec =
            (incoming['remaining_seconds'] as num?)?.toInt() ?? -1;

        setState(() {
          if (endMs > 0) {
            _targetEndTimeMs = endMs;
            final diff =
                (endMs - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
            _remainingSeconds = diff > 0 ? diff : 0;
          } else if (remSec >= 0) {
            _remainingSeconds = remSec;
            _targetEndTimeMs =
                DateTime.now().millisecondsSinceEpoch + (remSec * 1000);
          }
          _raidData = {
            ..._raidData,
            ...incoming,
            'roomId': roomId,
          };
          _isRaidDataLoaded = true;
        });
      }
    });

    final ok = await _lanSocket.connect(wsUrl);
    if (ok) {
      _lanSocket.sendJson({
        'type': 'join',
        'role': 'tv',
        'room': roomId,
        'roomId': roomId,
        'hunterId': 'tv_${Random().nextInt(999999)}',
        'name': 'Arena_TV',
      });
    }
    if (mounted) setState(() {});
  }

  void _recordActivity() {
    _lastRoomActivityMs = DateTime.now().millisecondsSinceEpoch;
  }

  void _markDormantAndStopAllTimers() {
    _queueRetryTimer?.cancel();
    _raidSubscription?.cancel();
    _raidSubscription = null;

    if (_isRadioPlaying) {
      _isRadioPlaying = false;
      AudioService.stopNrjStream();
    }

    if (_isLanMode) {
      _lanSocket.disconnect();
      return;
    }

    if (_raidRef != null && _lastKnownHunterCount > 0 && !_isQuotaExhausted) {
      _raidRef!.update({
        'status': 'dormant',
        'audio_playing': false,
      }).catchError((_) {});
    }
  }

  void _triggerQuotaExhaustedPodium() {
    _queueRetryTimer?.cancel();
    _raidSubscription?.cancel();
    _raidSubscription = null;
    if (_isRadioPlaying) {
      _isRadioPlaying = false;
      AudioService.stopNrjStream();
    }
    if (!mounted) return;
    setState(() {
      _isQuotaExhausted = true;
      _isAllocating = false;
      _isWorldSaturated = false;
      _isRaidDataLoaded = true;
    });
  }

  Future _triggerDefeat() async {
    _currentRaidStatus = 'failed';
    if (_isRadioPlaying) {
      _isRadioPlaying = false;
      AudioService.stopNrjStream();
    }
    if (_isLanMode) return;
    if (_raidRef != null) {
      bool canWrite =
          await QuotaGuardService.checkAndIncrementWrite(isCriticalClosure: true);
      if (canWrite) {
        await _raidRef!.update({
          'status': 'failed',
          'audio_playing': false,
          'last_activity_ms': DateTime.now().millisecondsSinceEpoch,
        }).timeout(_kFirestoreTimeout).catchError((_) {});
      } else {
        _triggerQuotaExhaustedPodium();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _markDormantAndStopAllTimers();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final params = _readUrlParams();
    final isLan = (params['mode']?.toLowerCase() == 'lan') ||
        (params['ws'] != null && params['ws']!.isNotEmpty);

    if (isLan) {
      if (!_isLanMode) {
        final room = (params['room'] ?? 'LAN_1').trim();
        final fallbackWs = _resolveDefaultLanWsUrl();
        final wsUrl = (params['ws'] ?? fallbackWs).trim();
        _connectLanTv(room.isEmpty ? 'LAN_1' : room,
            wsUrl.isEmpty ? fallbackWs : wsUrl);
      }
      return;
    }

    final now = DateTime.now();
    bool isNightClosed =
        (now.hour >= 0 && now.hour < 6) || (now.hour == 23 && now.minute >= 58);
    if (isNightClosed) {
      setState(() {
        _isNightLockActive = true;
        _isAllocating = false;
      });
      return;
    }
    if (_roomId == null &&
        !_isWorldSaturated &&
        !_isNightLockActive &&
        !_isQuotaExhausted &&
        !_isDespawnedForInactivity) {
      _resolveRoomAllocation();
    }
  }

  String _generateRandomToken(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }

  Future _resolveRoomAllocation() async {
    final now = DateTime.now();
    bool isNightClosed =
        (now.hour >= 0 && now.hour < 6) || (now.hour == 23 && now.minute >= 58);
    if (isNightClosed) {
      if (mounted) {
        setState(() {
          _isAllocating = false;
          _isNightLockActive = true;
        });
      }
      return;
    }

    if (await QuotaGuardService.isReserveReached()) {
      _triggerQuotaExhaustedPodium();
      return;
    }

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {}

    _recordActivity();

    final fullUrl = Uri.decodeFull(Uri.base.toString());
    String? explicitRoom;

    final roomRegex = RegExp(r'[?&]room=([a-zA-Z0-9_]+)');
    final match = roomRegex.firstMatch(fullUrl);
    if (match != null) {
      explicitRoom = match.group(1);
    }

    final String myInstanceToken = 'inst_${_generateRandomToken(12)}';
    String keyToUse = _generateRandomToken(6);
    String tokenToUse = _generateRandomToken(8);
    String? chosenRoom;

    if (explicitRoom != null && explicitRoom.trim().isNotEmpty) {
      chosenRoom = explicitRoom.trim();
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        _triggerQuotaExhaustedPodium();
        return;
      }

      final ref = FirebaseFirestore.instance
          .collection('current_raids')
          .doc(chosenRoom);
      final midnight = DateTime(now.year, now.month, now.day, 23, 58, 0);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      try {
        final existingDoc = await ref.get().timeout(_kFirestoreTimeout);

        if (!existingDoc.exists) {
          await ref.set({
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
            'last_activity_ms': nowMs,
          }).timeout(_kFirestoreTimeout);
        } else {
          final Map data = existingDoc.data() ?? {};
          final String existingKey =
              (data['admin_key'] ?? '').toString().trim();
          final String existingToken =
              (data['join_token'] ?? '').toString().trim();

          if (existingKey.isNotEmpty) keyToUse = existingKey;
          if (existingToken.isNotEmpty) tokenToUse = existingToken;

          await ref.set({
            'roomId': chosenRoom,
            'instance_token': myInstanceToken,
            'join_token': tokenToUse,
            'admin_key': keyToUse,
            'status': data['status'] == 'dormant'
                ? 'waiting'
                : (data['status'] ?? 'waiting'),
            'preset_label': data['preset_label'] ?? 'RAID STANDARD (5 000 PV)',
            'current_hp': data['current_hp'] ?? 5000,
            'max_hp': data['max_hp'] ?? 5000,
            'audio_playing': false,
            'hunters': data['hunters'] ?? [],
            'logs': data['logs'] ?? [],
            'target_end_time':
                data['target_end_time'] ?? midnight.millisecondsSinceEpoch,
            'last_activity_ms': nowMs,
          }).timeout(_kFirestoreTimeout);
        }
      } catch (e) {
        if (e.toString().toLowerCase().contains('resource-exhausted') ||
            e.toString().toLowerCase().contains('quota')) {
          _triggerQuotaExhaustedPodium();
          return;
        }
        if (!mounted) return;
        setState(() {
          _isAllocating = false;
          _isNightLockActive = true;
        });
        return;
      }
    } else {
      chosenRoom = await _claimNextAvailableRoomSlot(
          myInstanceToken, tokenToUse, keyToUse);
    }

    if (!mounted || _isQuotaExhausted) return;

    if (chosenRoom == null) {
      setState(() {
        _isAllocating = false;
        _isWorldSaturated = true;
      });

      _queueRetryTimer?.cancel();
      _queueRetryTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && !_isQuotaExhausted) {
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
    _recordActivity();

    final ref =
        FirebaseFirestore.instance.collection('current_raids').doc(chosenRoom);

    if (!mounted || _isQuotaExhausted) return;

    setState(() {
      _roomId = chosenRoom;
      _adminKey = keyToUse;
      _joinToken = tokenToUse;
      _raidRef = ref;
      _isAllocating = false;
      _isWorldSaturated = false;
      _isDespawnedForInactivity = false;
    });

    _startListeningToRaid();
  }

  void _startListeningToRaid() {
    if (_isLanMode ||
        _raidSubscription != null ||
        _raidRef == null ||
        _isQuotaExhausted) {
      return;
    }

    _raidSubscription = _raidRef!.snapshots().listen((doc) async {
      if (!mounted) return;
      if (doc.exists) {
        final Map mapData = Map.from(doc.data() as Map? ?? {});
        final double maxHp = ((mapData['max_hp'] ?? 5000) as num).toDouble();
        final double hp = ((mapData['current_hp'] ?? maxHp) as num).toDouble();
        final String st = (mapData['status'] ?? 'waiting').toString();
        final dynamic rawHunters = mapData['hunters'];
        final int hunterCount = rawHunters is Iterable ? rawHunters.length : 0;

        final bool remoteAudioPlaying = (mapData['audio_playing'] == true);
        if (remoteAudioPlaying != _isRadioPlaying) {
          _isRadioPlaying = remoteAudioPlaying;
          AudioService.setNrjStreamState(_isRadioPlaying);
        }

        if (hunterCount != _lastKnownHunterCount ||
            hp != _lastKnownHp ||
            st != _lastKnownStatus) {
          _recordActivity();
          _lastKnownHunterCount = hunterCount;
          _lastKnownHp = hp;
          _lastKnownStatus = st;
        }

        if (hp <= 0 && st == 'active') {
          _lastKnownStatus = 'victory';
          bool canWrite = await QuotaGuardService.checkAndIncrementWrite(
              isCriticalClosure: true);
          if (canWrite) {
            _raidRef!.update({
              'status': 'victory',
              'current_hp': 0,
              'audio_playing': false,
            }).catchError((_) {});
          } else {
            _triggerQuotaExhaustedPodium();
            return;
          }
          mapData['status'] = 'victory';
          mapData['current_hp'] = 0;

          if (_isRadioPlaying) {
            _isRadioPlaying = false;
            AudioService.setNrjStreamState(false);
          }
        }

        setState(() {
          _raidData = mapData;
          _isRaidDataLoaded = true;
          _isWorldSaturated = false;
        });
      } else {
        setState(() {
          _raidData = {};
          _isRaidDataLoaded = true;
        });
      }
    }, onError: (e) {
      debugPrint("[ARENA STREAM ERROR] $e");
      final String errStr = e.toString().toLowerCase();

      if (errStr.contains('resource-exhausted') || errStr.contains('quota')) {
        _triggerQuotaExhaustedPodium();
      } else if (errStr.contains('permission-denied')) {
        FirebaseAuth.instance.signInAnonymously().then((_) {
          if (mounted && !_isQuotaExhausted) {
            _raidSubscription?.cancel();
            _raidSubscription = null;
            _startListeningToRaid();
          }
        }).catchError((_) {});
      }
    });
  }

  Future<String?> _claimNextAvailableRoomSlot(
    String instanceToken,
    String joinToken,
    String adminKey,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final midnight = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      23,
      58,
      0,
    );

    Map<String, dynamic> buildFreshRoomData(String roomName) => {
          'roomId': roomName,
          'instance_token': instanceToken,
          'join_token': joinToken,
          'admin_key': adminKey,
          'status': 'waiting',
          'preset_label': 'RAID STANDARD (5 000 PV)',
          'current_hp': 5000,
          'max_hp': 5000,
          'audio_playing': false,
          'hunters': [],
          'logs': [],
          'target_end_time': midnight.millisecondsSinceEpoch,
          'last_activity_ms': now,
        };

    bool isSlotAvailable(DocumentSnapshot doc) {
      if (!doc.exists) return true;
      final Map data = doc.data() as Map? ?? {};
      final String st = (data['status'] ?? 'waiting').toString();
      if (st == 'dormant' || st == 'victory' || st == 'failed') {
        return true;
      }
      final int lastActivity = (data['last_activity_ms'] as num?)?.toInt() ??
          (data['arena_last_seen'] as num?)?.toInt() ??
          0;
      return lastActivity == 0 ||
          (now - lastActivity > kRoomInactivityThresholdMs);
    }

    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        _triggerQuotaExhaustedPodium();
        return null;
      }

      final rand = Random();
      final Set<int> tested = {};

      for (int attempt = 0; attempt < 6; attempt++) {
        int candidate = rand.nextInt(kMaxGlobalRooms) + 1;
        while (tested.contains(candidate) && tested.length < kMaxGlobalRooms) {
          candidate = (candidate % kMaxGlobalRooms) + 1;
        }
        tested.add(candidate);

        final roomName = 'room_$candidate';
        final docRef = firestore.collection('current_raids').doc(roomName);
        final doc = await docRef.get().timeout(_kFirestoreTimeout);

        if (isSlotAvailable(doc)) {
          await docRef
              .set(buildFreshRoomData(roomName))
              .timeout(_kFirestoreTimeout);
          return roomName;
        }
      }

      final snapshot = await firestore
          .collection('current_raids')
          .get()
          .timeout(_kFirestoreTimeout);
      final Set<int> occupiedNumbers = {};

      for (final doc in snapshot.docs) {
        if (doc.id.startsWith('room_')) {
          final numPart = int.tryParse(doc.id.replaceFirst('room_', ''));
          if (numPart != null && !isSlotAvailable(doc)) {
            occupiedNumbers.add(numPart);
          }
        }
      }

      int candidate = 1;
      while (occupiedNumbers.contains(candidate) &&
          candidate <= kMaxGlobalRooms) {
        candidate++;
      }

      if (candidate > kMaxGlobalRooms) {
        return null;
      }

      final allocatedRoom = 'room_$candidate';
      await firestore
          .collection('current_raids')
          .doc(allocatedRoom)
          .set(buildFreshRoomData(allocatedRoom))
          .timeout(_kFirestoreTimeout);

      return allocatedRoom;
    } catch (e) {
      if (e.toString().toLowerCase().contains('resource-exhausted') ||
          e.toString().toLowerCase().contains('quota')) {
        _triggerQuotaExhaustedPodium();
      }
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
    _lanSub?.cancel();
    _lanSocket.dispose();
    _markDormantAndStopAllTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isNightLockActive && !_isLanMode) {
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
                  style: TextStyle(
                      color: Color(0xFFFF2E56),
                      fontFamily: 'monospace',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
                SizedBox(height: 12),
                Text(
                  "Le quota d'énergie du Donjon est en repos nocturne.\nReposez votre Hardware. Réouverture automatique à 6h00 du matin.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isQuotaExhausted && !_isLanMode) {
      final Map data = _raidData;
      final double maxHp = ((data['max_hp'] ?? 5000) as num).toDouble();
      final double safeMax = maxHp > 0 ? maxHp : 5000.0;
      final double currentHp = ((data['current_hp'] ?? safeMax) as num)
          .toDouble()
          .clamp(0.0, safeMax);
      final String presetLabel =
          (data['preset_label'] ?? 'RAID STANDARD (5 000 PV)').toString();
      final dynamic rawHunters = data['hunters'];
      final List hunters = rawHunters is Iterable ? rawHunters.toList() : [];
      final dynamic rawLogs = data['logs'];
      final List logs = rawLogs is Iterable ? rawLogs.toList() : [];

      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2E56).withOpacity(0.22),
                    border:
                        Border.all(color: const Color(0xFFFF2E56), width: 1.5),
                  ),
                  child: const Text(
                    "⚠ DONJON ÉPUISÉ — REVENIR DEMAIN (QUOTA JOURNALIER ATTEINT) ⚠",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.4),
                  ),
                ),
                _buildTopHeader(currentHp, safeMax, true, false, presetLabel),
                const SizedBox(height: 10),
                Expanded(child: _buildCompleteMultiWayPodium(logs, hunters)),
              ],
            ),
          ),
        ),
      );
    }

    if (_isWorldSaturated && !_isLanMode) {
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
                CircularProgressIndicator(
                    color: Color(0xFFFF9100), strokeWidth: 3),
                SizedBox(height: 24),
                Text(
                  "PORTAILS MONDIAUX SATURÉS",
                  style: TextStyle(
                      color: Color(0xFFFF9100),
                      fontFamily: 'monospace',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
                SizedBox(height: 12),
                Text(
                  "Les 100 failles dimensionnelles sont actuellement engagées en combat.\nEn attente de libération d'un slot... (Nouvelle tentative dans 10 secondes)",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isAllocating || (!_isLanMode && _raidRef == null) || !_isRaidDataLoaded) {
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
                    letterSpacing: 2),
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
                Icon(Icons.portable_wifi_off,
                    color: Color(0xFFFF2E56), size: 54),
                SizedBox(height: 16),
                Text(
                  "LE PORTAIL S'EST REFERMÉ",
                  style: TextStyle(
                      color: Color(0xFFFF2E56),
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Map data = _raidData;
    final String status = (data['status'] ?? 'waiting').toString();
    final String presetLabel =
        (data['preset_label'] ?? 'RAID STANDARD (5 000 PV)').toString();
    final double maxHp = ((data['max_hp'] ?? 5000) as num).toDouble();
    final double safeMax = maxHp > 0 ? maxHp : 5000.0;
    final double currentHp =
        ((data['current_hp'] ?? safeMax) as num).toDouble().clamp(0.0, safeMax);
    final dynamic rawHunters = data['hunters'];
    final List hunters = rawHunters is Iterable ? rawHunters.toList() : [];
    final dynamic rawLogs = data['logs'];
    final List logs = rawLogs is Iterable ? rawLogs.toList() : [];

    final String dbJoinToken = (data['join_token'] ?? '').toString().trim();
    final String dbAdminKey = (data['admin_key'] ?? '').toString().trim();
    if (dbJoinToken.isNotEmpty && dbJoinToken != _joinToken) {
      _joinToken = dbJoinToken;
    }
    if (dbAdminKey.isNotEmpty && dbAdminKey != _adminKey) {
      _adminKey = dbAdminKey;
    }

    _currentRaidStatus = status;
    _currentBossHp = currentHp;

    if (!_isLanMode && data.containsKey('target_end_time')) {
      _syncTargetTime(data['target_end_time']);
    }

    final bool isDefeat = (status == 'failed') ||
        (_remainingSeconds == 0 &&
            (status == 'active' || status == 'failed') &&
            currentHp > 0);
    final bool isVictory = (status == 'victory') || (currentHp <= 0);

    Widget innerContent;
    if (isVictory) {
      innerContent = _buildCompleteMultiWayPodium(logs, hunters);
    } else if (isDefeat) {
      innerContent = _buildDefeatScreen(currentHp, safeMax, logs, hunters);
    } else {
      innerContent = status == 'waiting'
          ? _buildWaitingLobby(hunters)
          : _buildCombatWithMiniPodiumPanel(logs, hunters);
    }

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
                child:
                    _buildDynamicMaximizedQrPanel(status, isVictory: isVictory),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              if (_remainingSeconds > 0 &&
                  _remainingSeconds <= 600 &&
                  !isVictory &&
                  !isDefeat)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2E56).withOpacity(0.2),
                    border: Border.all(color: const Color(0xFFFF2E56)),
                  ),
                  child: const Text(
                    "⚠ ALERTE : LE DONJON MONDIAL SE REFERME À 23H58. FIN DE LA PÉRIODE D'ASSAUT IMMINENTE.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFFFF2E56),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.1),
                  ),
                ),
              _buildTopHeader(
                  currentHp, safeMax, isVictory, isDefeat, presetLabel),
              const SizedBox(height: 10),
              Expanded(child: mainContent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(double currentHp, double maxHp, bool isVictory,
      bool isDefeat, String presetLabel) {
    final double safeMax = maxHp > 0 ? maxHp : 5000.0;
    final double hpRatio = (currentHp / safeMax).clamp(0.0, 1.0);

    Color themeColor = const Color(0xFF00E5FF);
    String titleText = _isLanMode
        ? 'DONJON LAN [SALLE : ${_roomId ?? "LAN_1"}] • ${_lanSocket.isConnected ? "WS OK" : "WS HORS-LIGNE"}'
        : 'DONJON QUOTIDIEN [SALLE : ${_roomId ?? "HORS-LIGNE"}]';

    if (_isQuotaExhausted && !_isLanMode) {
      themeColor = const Color(0xFFFFD700);
      titleText = 'DONJON ÉPUISÉ — CLASSEMENT FINAL';
    } else if (isVictory) {
      themeColor = const Color(0xFFFFD700);
      titleText = 'SALLE [$_roomId] : MONARQUE DU FEU TERRASSÉ';
    } else if (isDefeat) {
      themeColor = const Color(0xFFFF2E56);
      titleText = 'SALLE [$_roomId] : ÉCHEC DU DONJON (TEMPS ÉCOULÉ)';
    }

    return Container(
      padding: const EdgeInsets.all(12),
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
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "CONFIGURATION : $presetLabel (BOSS: ${currentHp.toInt()} / ${safeMax.toInt()} PV)",
                      style: const TextStyle(
                          color: Color(0xFF00FF66),
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    height: 30,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00E5FF),
                        side: const BorderSide(
                            color: Color(0xFF00E5FF), width: 1.2),
                        backgroundColor:
                            const Color(0xFF00E5FF).withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: (_isQuotaExhausted && !_isLanMode)
                          ? null
                          : () async {
                              if (!_isLanMode) {
                                bool canWrite = await QuotaGuardService
                                    .checkAndIncrementWrite();
                                if (!canWrite) {
                                  _triggerQuotaExhaustedPodium();
                                  return;
                                }
                              }

                              final bool nextState = !_isRadioPlaying;
                              _isRadioPlaying = nextState;
                              bool playing =
                                  await AudioService.setNrjStreamState(
                                      nextState);
                              if (!_isLanMode && _raidRef != null) {
                                await _raidRef!.update({
                                  'audio_playing': nextState,
                                  'last_activity_ms':
                                      DateTime.now().millisecondsSinceEpoch,
                                }).catchError((_) {});
                              }
                              setState(() {});
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(playing
                                        ? "[AUDIO] Lecture en cours..."
                                        : "[AUDIO] Musique en pause."),
                                    duration:
                                        const Duration(milliseconds: 800),
                                  ),
                                );
                              }
                            },
                      icon: Icon(
                        AudioService.isPlaying ? Icons.pause : Icons.volume_up,
                        size: 14,
                      ),
                      label: Text(
                        AudioService.isPlaying ? "PAUSE" : "AUDIO",
                        style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Text(
                    'FIN : ${_formatTimer(_remainingSeconds)}',
                    style: TextStyle(
                      color: isDefeat || (_remainingSeconds <= 60 && !isVictory)
                          ? const Color(0xFFFF2E56)
                          : Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight:
                          isDefeat ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: 18,
                    color: Colors.black45,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    width: constraints.maxWidth * hpRatio,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2E56),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2E56).withOpacity(0.8),
                          blurRadius: 8,
                          spreadRadius: 1,
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

  Widget _buildDefeatScreen(
      double currentHp, double maxHp, List logs, List hunters) {
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFF2E56), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dangerous_outlined,
              color: Color(0xFFFF2E56), size: 60),
          const SizedBox(height: 10),
          const Text(
            "☠ ÉCHEC DU RAID ☠",
            style: TextStyle(
                color: Color(0xFFFF2E56),
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          const Text(
            "Le temps imparti est écoulé. Le Monarque du Feu a survécu à votre assaut.",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDefeatStatBox(
                  "DÉGÂTS", "$totalInflicted PV", const Color(0xFF00E5FF)),
              const SizedBox(width: 12),
              _buildDefeatStatBox("RESTANTS", "${currentHp.toInt()} PV",
                  const Color(0xFFFF2E56)),
              const SizedBox(width: 12),
              _buildDefeatStatBox(
                  "CHASSEURS", "${hunters.length}", const Color(0xFFFF9100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDefeatStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black45,
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontFamily: 'monospace',
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E).withOpacity(0.8),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.6), width: 1.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.leaderboard,
                        color: Color(0xFFFFD700), size: 14),
                    SizedBox(width: 6),
                    Text(
                      "CLASSEMENT PROVISOIRE (TOP 3 EN DIRECT)",
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (liveTop3.isEmpty)
                  const Text(
                    "En attente des premières frappes...",
                    style: TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                        fontFamily: 'monospace'),
                  )
                else
                  Row(
                    children: List.generate(liveTop3.length, (idx) {
                      final item = liveTop3[idx];
                      final Color medalColor = idx == 0
                          ? const Color(0xFFFFD700)
                          : (idx == 1
                              ? const Color(0xFFC0C0C0)
                              : const Color(0xFFCD7F32));
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                              right: idx < liveTop3.length - 1 ? 6 : 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: medalColor.withOpacity(0.08),
                            border: Border.all(
                                color: medalColor.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                "#${idx + 1}",
                                style: TextStyle(
                                    color: medalColor,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.key.toString(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                "${item.value} PV",
                                style: TextStyle(
                                    color: medalColor,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10),
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
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REGISTRE DES ASSAUTS',
                style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                'DERNIÈRE FRAPPE EN HAUT ↑',
                style: TextStyle(
                    color: Color(0xFF00FF66),
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: logList.isEmpty
                ? const Center(
                    child: Text(
                      'COMBAT COMMENCÉ : EN ATTENTE DU PREMIER ASSAUT',
                      style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    itemCount: logList.length,
                    itemBuilder: (context, index) {
                      final Map log =
                          logList[index] is Map ? logList[index] : {};
                      final String name =
                          (log['name'] ?? 'Chasseur').toString();
                      final String action =
                          (log['action'] ?? 'Frappe').toString();
                      final int damage =
                          (log['damage'] as num?)?.toInt() ?? 0;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border:
                              Border.all(color: Colors.white10, width: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flash_on,
                                color: Color(0xFF00E5FF), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    ': $action',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '-$damage PV',
                              style: const TextStyle(
                                  color: Color(0xFFFF9100),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  fontSize: 11),
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
    final Map huntersByMode = {};

    int globalSquats = 0;
    int globalPushups = 0;
    int globalAbs = 0;

    for (final rawH in hunters) {
      if (rawH is Map) {
        final Map<String, dynamic> hunterMap =
            Map<String, dynamic>.from(rawH);
        final String modeLabel =
            (hunterMap['mode_label'] ?? 'Entraînement du Monarque').toString();

        huntersByMode.putIfAbsent(modeLabel, () => []);
        huntersByMode[modeLabel]!.add(hunterMap);

        globalSquats += (hunterMap['squat_reps'] as num?)?.toInt() ?? 0;
        globalPushups += (hunterMap['pushup_reps'] as num?)?.toInt() ?? 0;
        globalAbs += (hunterMap['abs_reps'] as num?)?.toInt() ?? 0;
      }
    }

    final int grandTotalReps = globalSquats + globalPushups + globalAbs;

    final List allModes = [
      "Entraînement du Monarque (Squats, Pompes, Abdos)",
      "Voie des Jambes (Uniquement Squats)",
      "Voie du Haut (Uniquement Pompes)",
      "Voie du Tronc (Uniquement Abdos)",
      "Force Brute (Squats + Pompes)",
      "Jambes & Tronc (Squats + Abdos)",
      "Haut & Tronc (Pompes + Abdos)"
    ];

    for (final m in allModes) {
      huntersByMode.putIfAbsent(m, () => []);
    }

    final List entries = huntersByMode.entries.toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              _isQuotaExhausted
                  ? "★ DONJON ÉPUISÉ — REVENIR DEMAIN (PODIUM ACTUEL) ★"
                  : "★ PANTHÉON DU DONJON : LES 7 VOIES D'ENTRAÎNEMENT ★",
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.12),
              border: Border.all(color: const Color(0xFFFFD700), width: 1),
            ),
            child: Text(
              "TOTAL GLOBAL : $grandTotalReps REPS (Squats: $globalSquats | Pompes: $globalPushups | Abdos: $globalAbs)",
              style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GridView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: entries.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.1,
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final String modeName = entry.key.toString();
                    final List rawList =
                        entry.value is List ? entry.value : [];
                    final List modeHunters = rawList
                        .map((e) => Map<String, dynamic>.from(e))
                        .toList();

                    modeHunters.sort((a, b) {
                      final dmgA = (a['total_damage'] as num?)?.toInt() ?? 0;
                      final dmgB = (b['total_damage'] as num?)?.toInt() ?? 0;
                      return dmgB.compareTo(dmgA);
                    });

                    return Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        border: Border.all(
                            color: const Color(0xFF00E5FF).withOpacity(0.5),
                            width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.fitness_center,
                                  color: Color(0xFF00E5FF), size: 10),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  modeName.toUpperCase(),
                                  style: const TextStyle(
                                      color: Color(0xFF00E5FF),
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 8),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 4),
                          Expanded(
                            child: modeHunters.isEmpty
                                ? const Center(
                                    child: Text(
                                      "Vide",
                                      style: TextStyle(
                                          color: Colors.white30,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 8,
                                          fontFamily: 'monospace'),
                                    ),
                                  )
                                : ListView(
                                    padding: EdgeInsets.zero,
                                    children: List.generate(modeHunters.length,
                                        (idx) {
                                      final h = modeHunters[idx];
                                      final String name =
                                          (h['name'] ?? 'Chasseur').toString();
                                      final int dmg =
                                          (h['total_damage'] as num?)
                                                  ?.toInt() ??
                                              0;

                                      final Color rankColor = idx == 0
                                          ? const Color(0xFFFFD700)
                                          : (idx == 1
                                              ? const Color(0xFFC0C0C0)
                                              : const Color(0xFFCD7F32));

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 1.0),
                                        child: Row(
                                          children: [
                                            Text(
                                              "#${idx + 1}",
                                              style: TextStyle(
                                                  color: rankColor,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace'),
                                            ),
                                            const SizedBox(width: 3),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontFamily: 'monospace',
                                                    fontSize: 8),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              "$dmg",
                                              style: TextStyle(
                                                  color: rankColor,
                                                  fontFamily: 'monospace',
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingLobby(List hunterList) {
    final String countLabel = _isLanMode
        ? '${hunterList.length} CHASSEURS'
        : '${hunterList.length} / $kMaxHuntersPerRoom CHASSEURS';
    final Color countColor =
        (!_isLanMode && hunterList.length >= kMaxHuntersPerRoom)
            ? const Color(0xFFFF2E56)
            : const Color(0xFF00FF66);

    return Container(
      padding: const EdgeInsets.all(12),
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
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                countLabel,
                style: TextStyle(
                  color: countColor,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: hunterList.isEmpty
                ? const Center(
                    child: Text(
                      'AUCUN CHASSEUR DÉTECTÉ\nEN ATTENTE DU SCAN...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          letterSpacing: 1.1),
                    ),
                  )
                : ListView.builder(
                    itemCount: hunterList.length,
                    itemBuilder: (context, index) {
                      final Map h =
                          hunterList[index] is Map ? hunterList[index] : {};
                      final String name =
                          (h['name'] ?? 'Chasseur').toString();
                      final String mode =
                          (h['mode_label'] ?? 'Arsenal').toString();

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield,
                                color: Color(0xFF00E5FF), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11)),
                                  Text(mode,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 9)),
                                ],
                              ),
                            ),
                            const Text(
                              'PRÊT',
                              style: TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10),
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

  Widget _buildDynamicMaximizedQrPanel(String raidStatus,
      {required bool isVictory}) {
    final Uri? lanWsUri = Uri.tryParse(_lanWsUrl);
    final String lanHost = (lanWsUri != null && lanWsUri.host.isNotEmpty)
        ? lanWsUri.host
        : (Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1');
    final int lanPort = Uri.base.port != 0 ? Uri.base.port : 8080;
    final String lanScheme =
        Uri.base.scheme.isNotEmpty ? Uri.base.scheme : 'http';

    final String rawJoinUrl = _isLanMode
        ? '$lanScheme://$lanHost:$lanPort/?mode=lan&role=hunter&room=$_roomId&ws=${Uri.encodeComponent(_lanWsUrl)}'
        : 'https://shadowburn-1d8f8.web.app/#/join?room=$_roomId&token=${_joinToken ?? ""}';
    final String rawAdminAppUrl =
        'shadowburn://admin?room=$_roomId&key=${_adminKey ?? ""}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E).withOpacity(0.9),
        border: Border.all(
            color: const Color(0xFF00E5FF).withOpacity(0.6), width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_isLanMode) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'SCAN CHASSEUR LAN',
                  style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.1),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Image.network(
                          'https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${Uri.encodeComponent(rawJoinUrl)}',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.qr_code_2,
                                  size: 60, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Salle : $_roomId',
                  style: const TextStyle(
                      color: Color(0xFF00FF66),
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  '($_lanWsUrl)',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 8,
                      fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }

          final double totalHeight = constraints.maxHeight;
          final double sectionHeight = (totalHeight - 16) / 2;

          return Column(
            children: [
              SizedBox(
                height: sectionHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'SCAN CHASSEUR',
                      style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Image.network(
                              'https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${Uri.encodeComponent(rawJoinUrl)}',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.qr_code_2,
                                      size: 60, color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      raidStatus == 'waiting' ? '(En attente)' : '(Actif)',
                      style: TextStyle(
                          color: raidStatus == 'waiting'
                              ? Colors.white54
                              : const Color(0xFF00FF66),
                          fontSize: 8,
                          fontFamily: 'monospace'),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 3.0),
                child: Divider(color: Colors.white24, height: 1),
              ),
              SizedBox(
                height: sectionHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'TÉLÉCOMMANDE',
                      style: TextStyle(
                          color: Color(0xFFFF9100),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Image.network(
                              'https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${Uri.encodeComponent(rawAdminAppUrl)}',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.admin_panel_settings,
                                      size: 60, color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Salle : $_roomId',
                      style: const TextStyle(
                          color: Color(0xFFFF9100),
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold),
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