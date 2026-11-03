// lib/screens/hunter_join_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/multiplayer_quota_guard.dart';

const Color kSystemBlue = Color(0xFF00E5FF);
const String kAppDownloadUrl = "https://shadowburn-1d8f8.web.app";

class TrainingMode {
  final String id;
  final String label;
  final bool allowSquats;
  final bool allowPushups;
  final bool allowAbs;

  const TrainingMode({
    required this.id,
    required this.label,
    required this.allowSquats,
    required this.allowPushups,
    required this.allowAbs,
  });
}

class HunterJoinScreen extends StatefulWidget {
  const HunterJoinScreen({super.key});

  @override
  State<HunterJoinScreen> createState() => _HunterJoinScreenState();
}

class _HunterJoinScreenState extends State<HunterJoinScreen> with WidgetsBindingObserver {
  final TextEditingController _nameController = TextEditingController();

  String _roomId = '';
  String _token = '';
  DocumentReference? _raidRef;
  StreamSubscription? _raidSubscription;

  bool _isCheckingToken = true;
  bool _isTokenValid = false;
  bool _isWaitingQueue = false;
  bool _isNightLockActive = false;
  bool _isQuotaLockActive = false;
  bool _quotaGuardLoaded = false;
  String _denialReason = "VÉRIFICATION DU PORTAIL EN COURS...";

  bool _isJoined = false;
  bool _isLoading = false;
  String _confirmedHunterName = '';
  late final String _hunterSessionId;

  Timer? _inactivityWatchdogTimer;
  Timer? _queueRetryTimer;
  Map _raidData = {};
  bool _isRaidDataLoaded = false;

  int _comboStep = 0;
  int _frenzyRemainingSeconds = 0;
  Timer? _frenzyTimer;
  int _lastStrikeMs = 0;
  int _lastHunterActionMs = 0;
  int _antiCheatCooldownSeconds = 0;
  Timer? _antiCheatTimer;

  // CONTOURNEMENT RADICAL : List brute sans chevrons complexes pour éviter tout conflit de parser
  int _pendingDamage = 0;
  int _pendingSquatReps = 0;
  int _pendingPushupReps = 0;
  int _pendingAbsReps = 0;
  final List _pendingLogs = [];
  Timer? _batchFlushTimer;
  bool _isFlushing = false;

  static const int kMaxHuntersPerRoom = 10;
  static const int kBatchIntervalSeconds = 6;

  static const List trainingModes = [
    TrainingMode(
      id: 'all',
      label: 'Entraînement du Monarque (Squats, Pompes, Abdos)',
      allowSquats: true,
      allowPushups: true,
      allowAbs: true,
    ),
    TrainingMode(
      id: 'squats_only',
      label: 'Voie des Jambes (Uniquement Squats)',
      allowSquats: true,
      allowPushups: false,
      allowAbs: false,
    ),
    TrainingMode(
      id: 'pushups_only',
      label: 'Voie du Haut (Uniquement Pompes)',
      allowSquats: false,
      allowPushups: true,
      allowAbs: false,
    ),
    TrainingMode(
      id: 'abs_only',
      label: 'Voie du Tronc (Uniquement Abdos)',
      allowSquats: false,
      allowPushups: false,
      allowAbs: true,
    ),
    TrainingMode(
      id: 'squats_pushups',
      label: 'Force Brute (Squats + Pompes)',
      allowSquats: true,
      allowPushups: true,
      allowAbs: false,
    ),
    TrainingMode(
      id: 'squats_abs',
      label: 'Jambes & Tronc (Squats + Abdos)',
      allowSquats: true,
      allowPushups: false,
      allowAbs: true,
    ),
    TrainingMode(
      id: 'pushups_abs',
      label: 'Haut & Tronc (Pompes + Abdos)',
      allowSquats: false,
      allowPushups: true,
      allowAbs: true,
    ),
  ];

  late String _selectedModeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedModeId = (trainingModes.first as TrainingMode).id;

    final randomInt = Random().nextInt(999999);
    _hunterSessionId = 'chasseur_${DateTime.now().millisecondsSinceEpoch}_$randomInt';
    _autoDetectDeviceName(randomInt);
    unawaited(_loadQuotaGuard());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_quotaGuardLoaded) _parseIncomingParameters();
  }

  Future<void> _loadQuotaGuard() async {
    final bool paused = await MultiplayerQuotaGuard.isPaused();
    if (!mounted) return;
    setState(() {
      _isQuotaLockActive = paused;
      _quotaGuardLoaded = true;
    });
    if (!paused) _parseIncomingParameters();
  }

  void _activateQuotaLock() {
    _isQuotaLockActive = true;
    unawaited(MultiplayerQuotaGuard.pauseUntilSafeRetry());
    _inactivityWatchdogTimer?.cancel();
    _queueRetryTimer?.cancel();
    _batchFlushTimer?.cancel();
    _raidSubscription?.cancel();
    if (mounted) setState(() {});
  }

  void _parseIncomingParameters() {
    final now = DateTime.now();
    if (now.hour < 6 || now.hour >= 23) {
      if (mounted) {
        setState(() {
          _isCheckingToken = false;
          _isNightLockActive = true;
        });
      }
      return;
    }

    String rawUrl = Uri.base.toString();
    try {
      rawUrl = Uri.decodeFull(rawUrl);
    } catch (_) {}

    String? foundRoom;
    String? foundToken;

    final roomRegex = RegExp(r'[?&]room=([a-zA-Z0-9_]+)', caseSensitive: false);
    final tokenRegex = RegExp(r'[?&]token=([a-zA-Z0-9_]+)', caseSensitive: false);

    final roomMatch = roomRegex.firstMatch(rawUrl);
    if (roomMatch != null) {
      foundRoom = roomMatch.group(1);
    }

    final tokenMatch = tokenRegex.firstMatch(rawUrl);
    if (tokenMatch != null) {
      foundToken = tokenMatch.group(1);
    }

    foundRoom ??= Uri.base.queryParameters['room'];
    foundToken ??= Uri.base.queryParameters['token'];

    _roomId = (foundRoom != null && foundRoom.trim().isNotEmpty) ? foundRoom.trim() : '';
    _token = (foundToken != null && foundToken.trim().isNotEmpty) ? foundToken.trim() : '';

    _verifyPortalSecurity();
  }

  Future _verifyPortalSecurity() async {
    if (_isQuotaLockActive) return;
    final now = DateTime.now();
    if (now.hour < 6 || now.hour >= 23) {
      if (mounted) {
        setState(() {
          _isCheckingToken = false;
          _isNightLockActive = true;
        });
      }
      return;
    }

    if (_roomId.isEmpty) {
      if (mounted) {
        setState(() {
          _isCheckingToken = false;
          _isTokenValid = false;
          _denialReason = "ACCÈS REFUSÉ : SCAN DU QR CODE EN DIRECT OBLIGATOIRE.\nAucun identifiant de salle détecté dans l'URL.";
        });
      }
      return;
    }

    try {
      final ref = FirebaseFirestore.instance.collection('current_raids').doc(_roomId);
      final doc = await ref.get();

      if (!doc.exists) {
        if (mounted) {
          setState(() {
            _isCheckingToken = false;
            _isWaitingQueue = true;
          });
        }
        _queueRetryTimer?.cancel();
        _queueRetryTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() {
              _isCheckingToken = true;
              _isWaitingQueue = false;
            });
            _verifyPortalSecurity();
          }
        });
        return;
      }

      final Map data = doc.data() ?? {};
      final String expectedToken = (data['join_token'] ?? '').toString().trim().toUpperCase();
      final String receivedToken = _token.trim().toUpperCase();

      if (expectedToken.isNotEmpty && receivedToken != expectedToken) {
        if (mounted) {
          setState(() {
            _isCheckingToken = false;
            _isTokenValid = false;
            _denialReason = "JETON DU PORTAIL EXPIRÉ OU INVALIDE.\nRe-scannez le QR Code affiché sur l'écran TV de [$_roomId].";
          });
        }
        return;
      }

      final dynamic rawHunters = data['hunters'];
      final List hunterList = rawHunters is Iterable ? rawHunters.toList() : [];
      final int connectedHunters = hunterList.where(
        (hunter) => hunter is Map && hunter['is_connected'] != false,
      ).length;
      if (connectedHunters >= kMaxHuntersPerRoom) {
        if (mounted) {
          setState(() {
            _isCheckingToken = false;
            _isWaitingQueue = true;
          });
        }
        _queueRetryTimer?.cancel();
        _queueRetryTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() {
              _isCheckingToken = true;
              _isWaitingQueue = false;
            });
            _verifyPortalSecurity();
          }
        });
        return;
      }

      _queueRetryTimer?.cancel();

      if (mounted) {
        setState(() {
          _raidRef = ref;
          _raidData = data;
          _isRaidDataLoaded = true;
          _isCheckingToken = false;
          _isTokenValid = true;
          _isWaitingQueue = false;
        });
        _startListeningToRaid();
      }
    } catch (e) {
      if (e.toString().contains('resource-exhausted') || e.toString().contains('quota')) {
        if (mounted) setState(() => _isCheckingToken = false);
        _activateQuotaLock();
        return;
      }
      if (mounted) {
        setState(() {
          _isCheckingToken = false;
          _isTokenValid = false;
          _denialReason = "Erreur de synchronisation avec le Portail : $e";
        });
      }
    }
  }

  void _startListeningToRaid() {
    _raidSubscription?.cancel();
    if (_raidRef == null) return;

    _raidSubscription = _raidRef!.snapshots().listen((doc) {
      if (!mounted) return;
      setState(() {
        if (doc.exists) {
          final Map incoming = Map.from(doc.data() as Map? ?? {});
          final dynamic incLogs = incoming['logs'];
          final int incHp = (incoming['current_hp'] as num?)?.toInt() ?? 5000;
          if (incHp == 5000 && (incLogs is Iterable && incLogs.isEmpty)) {
            _pendingDamage = 0;
            _pendingSquatReps = 0;
            _pendingPushupReps = 0;
            _pendingAbsReps = 0;
            _pendingLogs.clear();
          }
          _raidData = incoming;
        } else {
          _raidData = {};
          _raidSubscription?.cancel();
        }
        _isRaidDataLoaded = true;
      });
    }, onError: (e) {
      if (e.toString().contains('resource-exhausted') || e.toString().contains('quota')) {
        _activateQuotaLock();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityWatchdogTimer?.cancel();
    _queueRetryTimer?.cancel();
    _raidSubscription?.cancel();
    _frenzyTimer?.cancel();
    _antiCheatTimer?.cancel();
    _batchFlushTimer?.cancel();
    _flushPendingDamage();
    super.dispose();
  }

  void _autoDetectDeviceName(int uniqueSeed) {
    String detected = "Chasseur_${uniqueSeed % 1000}";

    if (kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          detected = "Chasseur_iOS_${uniqueSeed % 1000}";
          break;
        case TargetPlatform.android:
          detected = "Chasseur_Droid_${uniqueSeed % 1000}";
          break;
        default:
          detected = "Chasseur_Web_${uniqueSeed % 1000}";
      }
    }

    _nameController.text = detected;
  }

  void _startInactivityWatchdog() {
    _lastHunterActionMs = DateTime.now().millisecondsSinceEpoch;
    _inactivityWatchdogTimer?.cancel();
    _inactivityWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isJoined || !mounted) return;
      final String st = (_raidData['status'] ?? 'waiting').toString();
      if (st != 'active') {
        _lastHunterActionMs = DateTime.now().millisecondsSinceEpoch;
        return;
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastHunterActionMs >= 60000) {
        _leaveRaid();
      }
    });
  }

  Future _joinRaid() async {
    if (_isQuotaLockActive) return;
    final name = _nameController.text.trim();
    if (name.isEmpty || _raidRef == null) return;

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final TrainingMode selectedMode = trainingModes.firstWhere(
        (m) => (m as TrainingMode).id == _selectedModeId,
      ) as TrainingMode;

      final Map<String, dynamic> hunterEntry = {
        'id': _hunterSessionId,
        'name': name,
        'rank': 'Rang E',
        'mode_id': _selectedModeId,
        'mode_label': selectedMode.label,
        'combo_step': 0,
        'total_damage': 0,
        'squat_reps': 0,
        'pushup_reps': 0,
        'abs_reps': 0,
        'joined_at': now,
        'last_seen': now,
        'is_connected': true,
      };

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final joinNow = DateTime.now();
        if (joinNow.hour < 6 || joinNow.hour >= 23) {
          throw StateError('Les portails sont fermés entre 23h et 6h.');
        }
        final latest = await transaction.get(_raidRef!);
        if (!latest.exists) throw StateError('Cette salle n’existe plus.');
        final Map<String, dynamic> latestData = latest.data() as Map<String, dynamic>? ?? {};
        final String currentToken = (latestData['join_token'] ?? '').toString().trim().toUpperCase();
        if (currentToken.isEmpty || currentToken != _token.trim().toUpperCase()) {
          throw StateError('Le jeton du portail a expiré. Scannez à nouveau le QR code.');
        }
        final String currentStatus = (latestData['status'] ?? 'waiting').toString();
        if (currentStatus != 'waiting' && currentStatus != 'active') {
          throw StateError('Ce donjon n’accepte plus de nouveaux chasseurs.');
        }
        final dynamic rawLatestHunters = latestData['hunters'];
        final List<dynamic> latestHunters = rawLatestHunters is Iterable
            ? List<dynamic>.from(rawLatestHunters)
            : <dynamic>[];
        final int existingIndex = latestHunters.indexWhere(
          (hunter) => hunter is Map && hunter['id'] == _hunterSessionId,
        );
        final int connectedCount = latestHunters.where(
          (hunter) => hunter is Map && hunter['is_connected'] != false,
        ).length;
        if (existingIndex == -1 && connectedCount >= kMaxHuntersPerRoom) {
          throw StateError('Cette salle est complète : 10 chasseurs maximum.');
        }
        if (existingIndex == -1) {
          latestHunters.add(hunterEntry);
        } else {
          final Map<String, dynamic> existingHunter =
              Map<String, dynamic>.from(latestHunters[existingIndex] as Map);
          existingHunter['is_connected'] = true;
          existingHunter['last_seen'] = now;
          latestHunters[existingIndex] = existingHunter;
        }
        transaction.update(_raidRef!, {'hunters': latestHunters});
      });

      setState(() {
        _isJoined = true;
        _confirmedHunterName = name;
        _isLoading = false;
      });

      _startInactivityWatchdog();
    } catch (e) {
      setState(() => _isLoading = false);
      if (e.toString().contains('resource-exhausted') || e.toString().contains('quota')) {
        _activateQuotaLock();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur d'accès au Donjon: $e"),
            backgroundColor: const Color(0xFFFF2E56),
          ),
        );
      }
    }
  }

  Future _leaveRaid() async {
    setState(() => _isLoading = true);
    _inactivityWatchdogTimer?.cancel();
    _frenzyTimer?.cancel();
    _antiCheatTimer?.cancel();
    _batchFlushTimer?.cancel();
    _batchFlushTimer = null;

    await _flushPendingDamage();

    try {
      if (_raidRef != null && _raidData.isNotEmpty) {
        final DocumentReference ref = _raidRef!;
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final latest = await transaction.get(ref);
          if (!latest.exists) return;
          final Map<String, dynamic> data = latest.data() as Map<String, dynamic>? ?? {};
          final dynamic rawLatestHunters = data['hunters'];
          final List<dynamic> latestHunters = rawLatestHunters is Iterable
              ? List<dynamic>.from(rawLatestHunters)
              : <dynamic>[];
          final int index = latestHunters.indexWhere(
            (hunter) => hunter is Map && hunter['id'] == _hunterSessionId,
          );
          if (index == -1) return;
          final Map<String, dynamic> hunter =
              Map<String, dynamic>.from(latestHunters[index] as Map);
          if ((hunter['total_damage'] as num?)?.toInt() == 0) {
            latestHunters.removeAt(index);
          } else {
            hunter['is_connected'] = false;
            hunter['last_seen'] = DateTime.now().millisecondsSinceEpoch;
            latestHunters[index] = hunter;
          }
          transaction.update(ref, {'hunters': latestHunters});
        });
      }

      if (mounted) {
        setState(() {
          _isJoined = false;
          _isLoading = false;
          _comboStep = 0;
          _frenzyRemainingSeconds = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resetFrenzyState() {
    _frenzyTimer?.cancel();
    _frenzyTimer = null;
    setState(() {
      _comboStep = 0;
      _frenzyRemainingSeconds = 0;
    });
  }

  void _handleExerciseTap(String category, String actionLabel) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastHunterActionMs = now;

    if (now - _lastStrikeMs < 2000) {
      final waitMs = 2000 - (now - _lastStrikeMs);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "CADENCE TROP RAPIDE ! Patientez ${(waitMs / 1000).toStringAsFixed(1)}s (Respectez le tempo 2-2-2).",
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          backgroundColor: const Color(0xFFFF2E56),
          duration: const Duration(milliseconds: 900),
        ),
      );
      return;
    }

    _lastStrikeMs = now;
    setState(() {
      _antiCheatCooldownSeconds = 2;
    });
    _antiCheatTimer?.cancel();
    _antiCheatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_antiCheatCooldownSeconds <= 1) {
          _antiCheatCooldownSeconds = 0;
          timer.cancel();
        } else {
          _antiCheatCooldownSeconds--;
        }
      });
    });

    int damage = 25;
    bool triggeredGlow = false;
    String feedback = "";
    bool isBurstFinish = false;

    if (_comboStep == 0) {
      _comboStep = 1;
      damage = 25;
      triggeredGlow = false;
      _frenzyRemainingSeconds = 10;
      feedback = "FRÉNÉSIE AMORCÉE ! Enchaînez dans les 10s (+150 PV) !";

      _frenzyTimer?.cancel();
      _frenzyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          if (_frenzyRemainingSeconds > 1) {
            _frenzyRemainingSeconds--;
          } else {
            _resetFrenzyState();
          }
        });
      });
    } else if (_comboStep == 1) {
      _frenzyTimer?.cancel();
      _comboStep = 2;
      damage = 150;
      triggeredGlow = true;
      _frenzyRemainingSeconds = 10;
      feedback = "★ SURBRILLANCE 150 PV ! Dernier palier dans les 10s (+200 PV) !";

      _frenzyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          if (_frenzyRemainingSeconds > 1) {
            _frenzyRemainingSeconds--;
          } else {
            _resetFrenzyState();
          }
        });
      });
    } else if (_comboStep == 2) {
      _frenzyTimer?.cancel();
      damage = 200;
      triggeredGlow = true;
      isBurstFinish = true;
      feedback = "★★ SURPASSEMENT CRITIQUE TOTAL : 200 PV INFLIGÉS !";

      _frenzyTimer = null;
      _frenzyRemainingSeconds = 0;
      _comboStep = 0;
    }

    setState(() {});
    _bufferStrike(damage, category, 5, actionLabel, triggeredGlow, feedback, forceImmediateFlush: isBurstFinish);
  }

  void _bufferStrike(
    int damage,
    String exerciseCategory,
    int repsCount,
    String actionLabel,
    bool glowEffect,
    String feedback, {
    bool forceImmediateFlush = false,
  }) {
    if (_raidRef == null) return;
    
    final Map data = _raidData;
    final String raidStatus = (data['status'] ?? 'waiting').toString();
    if (raidStatus != 'active') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("LE MAÎTRE DU JEU N'A PAS ENCORE LANCÉ LE RAID !"),
          backgroundColor: Color(0xFFFF9100),
        ),
      );
      return;
    }

    _pendingDamage += damage;
    if (exerciseCategory == 'squat') {
      _pendingSquatReps += repsCount;
    } else if (exerciseCategory == 'pushup') {
      _pendingPushupReps += repsCount;
    } else if (exerciseCategory == 'abs') {
      _pendingAbsReps += repsCount;
    }
    
    _pendingLogs.insert(0, {
      'id': _hunterSessionId,
      'name': _confirmedHunterName,
      'rank': 'Rang E',
      'category': exerciseCategory,
      'reps': repsCount,
      'action': actionLabel,
      'damage': damage,
      'glowing': glowEffect,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    final num currentHp = (data['current_hp'] as num?) ?? 5000;
    final double estimatedNewHp = (currentHp - damage).clamp(0.0, 5000.0).toDouble();
    setState(() {
      _raidData['current_hp'] = estimatedNewHp;
      final dynamic rawLogs = _raidData['logs'];
      final List logsList = rawLogs is Iterable ? List.from(rawLogs) : [];
      logsList.insert(0, _pendingLogs.first);
      if (logsList.length > 30) logsList.removeRange(30, logsList.length);
      _raidData['logs'] = logsList;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(feedback.isNotEmpty ? feedback : "-$damage PV infligés !"),
        backgroundColor: glowEffect ? const Color(0xFFFF2E56) : const Color(0xFF00FF66),
        duration: const Duration(seconds: 1),
      ),
    );

    if (estimatedNewHp <= 0 || forceImmediateFlush) {
      _batchFlushTimer?.cancel();
      _batchFlushTimer = null;
      _flushPendingDamage();
      return;
    }

    _batchFlushTimer ??= Timer(const Duration(seconds: kBatchIntervalSeconds), () {
      _batchFlushTimer = null;
      _flushPendingDamage();
    });
  }

    Future _flushPendingDamage() async {
    if (_isQuotaLockActive || _pendingDamage == 0 || _raidRef == null || _isFlushing) return;
    _isFlushing = true;
    
    final int dmgToSend = _pendingDamage;
    final int sToSend = _pendingSquatReps;
    final int pToSend = _pendingPushupReps;
    final int aToSend = _pendingAbsReps;
    final List logsToSend = List.from(_pendingLogs);
    
    _pendingDamage = 0;
    _pendingSquatReps = 0;
    _pendingPushupReps = 0;
    _pendingAbsReps = 0;
    _pendingLogs.clear();

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(_raidRef!);
        if (!snapshot.exists) return;
        
        final data = snapshot.data() as Map<String, dynamic>;
        final currentStatus = (data['status'] ?? 'waiting').toString();
        
        if (currentStatus != 'active') return;

        final int currentHp = (data['current_hp'] as num?)?.toInt() ?? 5000;
        final int nextHp = (currentHp - dmgToSend).clamp(0, 5000);
        
        final List logs = List.from(data['logs'] ?? []);
        logs.insertAll(0, logsToSend);
        if (logs.length > 30) logs.removeRange(30, logs.length);
        
        final List hunterList = List.from(data['hunters'] ?? []);
        bool foundHunter = false;
        for (int i = 0; i < hunterList.length; i++) {
          if (hunterList[i] is Map && hunterList[i]['id'] == _hunterSessionId) {
            final Map h = Map.from(hunterList[i]);
            h['total_damage'] = ((h['total_damage'] as num?)?.toInt() ?? 0) + dmgToSend;
            h['squat_reps'] = ((h['squat_reps'] as num?)?.toInt() ?? 0) + sToSend;
            h['pushup_reps'] = ((h['pushup_reps'] as num?)?.toInt() ?? 0) + pToSend;
            h['abs_reps'] = ((h['abs_reps'] as num?)?.toInt() ?? 0) + aToSend;
            h['last_seen'] = DateTime.now().millisecondsSinceEpoch;
            hunterList[i] = h;
            foundHunter = true;
            break;
          }
        }

        if (!foundHunter && _confirmedHunterName.isNotEmpty) {
          hunterList.add({
            'id': _hunterSessionId,
            'name': _confirmedHunterName,
            'rank': 'Rang E',
            'mode_id': _selectedModeId,
            'total_damage': dmgToSend,
            'squat_reps': sToSend,
            'pushup_reps': pToSend,
            'abs_reps': aToSend,
            'joined_at': DateTime.now().millisecondsSinceEpoch,
            'last_seen': DateTime.now().millisecondsSinceEpoch,
          });
        }
        
        transaction.update(_raidRef!, {
          'current_hp': nextHp,
          'logs': logs,
          'hunters': hunterList,
          if (nextHp <= 0) 'status': 'victory',
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      // Ne perds pas les dégâts si le réseau échoue : ils restent en attente d'un nouvel envoi.
      _pendingDamage += dmgToSend;
      _pendingSquatReps += sToSend;
      _pendingPushupReps += pToSend;
      _pendingAbsReps += aToSend;
      _pendingLogs.insertAll(0, logsToSend);
      debugPrint("[CHASSEUR] Erreur de synchronisation des dégâts : $e");
      final bool quotaExhausted = e.toString().contains('resource-exhausted') || e.toString().contains('quota');
      if (quotaExhausted) _activateQuotaLock();
      if (!quotaExhausted && mounted && _isJoined) {
        _batchFlushTimer?.cancel();
        _batchFlushTimer = Timer(const Duration(seconds: kBatchIntervalSeconds), () {
          _batchFlushTimer = null;
          _flushPendingDamage();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isFlushing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isQuotaLockActive) {
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
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFFFF9100), size: 64),
                SizedBox(height: 20),
                Text(
                  "PORTAIL MULTIJOUEUR EN PAUSE",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                SizedBox(height: 12),
                Text(
                  "Firebase a refusé une requête pour quota atteint. Les échanges sont suspendus. Vérifiez le quota du projet avant de relancer le portail.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                  "[ SYSTÈME : PORTAILS SCELLÉS (23H00 - 06H00) ]",
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

    if (_isWaitingQueue) {
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
                  "SALLE PLEINE OU EN ATTENTE",
                  style: TextStyle(
                    color: Color(0xFFFF9100),
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  "La salle a atteint son quota maximal de 10 Chasseurs ou est en cours d'allocation.\n"
                  "En attente de libération d'un slot... (Nouvelle tentative dans 30 secondes)",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isCheckingToken) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070D),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: kSystemBlue),
              SizedBox(height: 16),
              Text(
                "AUTHENTIFICATION DU PORTAIL...",
                style: TextStyle(color: kSystemBlue, fontFamily: 'monospace', letterSpacing: 2),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isTokenValid) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF04101E),
                border: Border.all(color: const Color(0xFFFF2E56), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_bad, color: Color(0xFFFF2E56), size: 54),
                  const SizedBox(height: 16),
                  const Text(
                    "ACCÈS AU DONJON INTERDIT",
                    style: TextStyle(
                      color: Color(0xFFFF2E56),
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _denialReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kSystemBlue,
                      side: const BorderSide(color: kSystemBlue),
                    ),
                    onPressed: () {
                      setState(() {
                        _isCheckingToken = true;
                      });
                      _parseIncomingParameters();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text(
                      "RÉESSAYER LA VÉRIFICATION",
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_isJoined,
      child: Scaffold(
        backgroundColor: const Color(0xFF02070D),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF04101E),
          centerTitle: true,
          title: Text(
            "SHADOWBURN : SALLE [$_roomId]",
            style: const TextStyle(
              color: kSystemBlue,
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: !_isJoined ? _buildLobbyEntry() : _buildLiveControllerPad(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyEntry() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: kSystemBlue.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: kSystemBlue.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined, color: kSystemBlue, size: 44),
          const SizedBox(height: 12),
          const Text(
            "ENRÔLEMENT DU CHASSEUR",
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Connexion certifiée par QR Code : $_roomId",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: "NOM DU CHASSEUR",
              labelStyle: const TextStyle(color: kSystemBlue, fontSize: 12),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kSystemBlue.withOpacity(0.5)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: kSystemBlue, width: 2),
              ),
              prefixIcon: const Icon(Icons.person, color: kSystemBlue),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField(
            value: _selectedModeId,
            isExpanded: true,
            dropdownColor: const Color(0xFF04101E),
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              labelText: "VOIE DE COMBAT (EXERCICES)",
              labelStyle: const TextStyle(color: kSystemBlue, fontSize: 12),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kSystemBlue.withOpacity(0.5)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: kSystemBlue, width: 2),
              ),
              prefixIcon: const Icon(Icons.fitness_center, color: kSystemBlue),
            ),
            items: trainingModes.map((rawMode) {
              final TrainingMode mode = rawMode as TrainingMode;
              return DropdownMenuItem(
                value: mode.id,
                child: Text(
                  mode.label,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedModeId = val.toString());
              }
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kSystemBlue,
                foregroundColor: Colors.black,
                shape: const BeveledRectangleBorder(),
              ),
              onPressed: _isLoading ? null : _joinRaid,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text(
                      "REJOINDRE LE DONJON",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveControllerPad() {
    if (!_isRaidDataLoaded) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    }

    if (_isRaidDataLoaded && _raidData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF04101E),
          border: Border.all(color: const Color(0xFFFF2E56), width: 2),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.portable_wifi_off, color: Color(0xFFFF2E56), size: 48),
            SizedBox(height: 12),
            Text(
              "LE PORTAIL S'EST REFERMÉ (INACTIVITÉ OU FIN)",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFF2E56),
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "La salle a été fermée ou mise en veille automatique après 60s d'inactivité.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
      );
    }

    final Map data = _raidData;
    String raidStatus = (data['status'] ?? 'waiting').toString();
    num currentHp = ((data['current_hp'] ?? 5000) as num).clamp(0, 5000);
    num maxHp = (data['max_hp'] as num?) ?? 5000;

    if (raidStatus == 'victory' || currentHp <= 0) {
      return _buildVictoryPodiumView(data);
    }

    final TrainingMode selectedMode = trainingModes.firstWhere(
      (m) => (m as TrainingMode).id == _selectedModeId,
    ) as TrainingMode;
    final bool isCombatActive = (raidStatus == 'active');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF04101E),
            border: Border.all(
              color: isCombatActive ? const Color(0xFF00FF66) : const Color(0xFFFF9100),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                "CHASSEUR : $_confirmedHunterName",
                style: const TextStyle(
                  color: kSystemBlue,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "${selectedMode.label} (Salle: $_roomId)",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCombatActive
                      ? const Color(0xFF00FF66).withOpacity(0.1)
                      : const Color(0xFFFF9100).withOpacity(0.1),
                  border: Border.all(
                    color: isCombatActive ? const Color(0xFF00FF66) : const Color(0xFFFF9100),
                  ),
                ),
                child: Text(
                  isCombatActive
                      ? "COMBAT EN COURS (BOSS: ${currentHp.toInt()} / $maxHp PV)"
                      : "EN ATTENTE DU MAÎTRE DU JEU...",
                  style: TextStyle(
                    color: isCombatActive ? const Color(0xFF00FF66) : const Color(0xFFFF9100),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (_frenzyRemainingSeconds > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _comboStep == 2
                        ? const Color(0xFFFF2E56).withOpacity(0.2)
                        : const Color(0xFFFF9100).withOpacity(0.15),
                    border: Border.all(
                      color: _comboStep == 2 ? const Color(0xFFFF2E56) : const Color(0xFFFF9100),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _comboStep == 2
                        ? "BURST 200 PV DISPONIBLE : $_frenzyRemainingSeconds s !"
                        : "FRÉNÉSIE 150 PV DISPONIBLE : $_frenzyRemainingSeconds s !",
                    style: TextStyle(
                      color: _comboStep == 2 ? const Color(0xFFFFD700) : const Color(0xFFFF9100),
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          "VOS IMPACTS PHYSIQUES (TEMPO 2-2-2) :",
          style: TextStyle(
            color: Colors.white70,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (selectedMode.allowSquats) ...[
          _exerciseButton(
            label: "SQUATS (5 REPS)",
            category: 'squat',
            color: kSystemBlue,
            isEnabled: isCombatActive,
          ),
          const SizedBox(height: 10),
        ],
        if (selectedMode.allowPushups) ...[
          _exerciseButton(
            label: "POMPES (5 REPS)",
            category: 'pushup',
            color: const Color(0xFFFF9100),
            isEnabled: isCombatActive,
          ),
          const SizedBox(height: 10),
        ],
        if (selectedMode.allowAbs) ...[
          _exerciseButton(
            label: "ABDOS (5 REPS)",
            category: 'abs',
            color: const Color(0xFF00FF66),
            isEnabled: isCombatActive,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        const Center(
          child: Text(
            "Protection Anti-Triche : 2s min entre chaque frappe. Déconnexion après 60s d'inactivité.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 9, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _isLoading ? null : _leaveRaid,
          icon: const Icon(Icons.exit_to_app, color: Colors.white38, size: 16),
          label: const Text(
            "QUITTER LE DONJON",
            style: TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVictoryPodiumView(Map data) {
    final dynamic rawHunters = data['hunters'];
    final List hunters = [];

    if (rawHunters is Iterable) {
      for (final item in rawHunters) {
        if (item is Map) {
          hunters.add(Map<String, dynamic>.from(item));
        }
      }
    }

    hunters.sort((a, b) {
      final num dmgA = (a['total_damage'] as num?) ?? 0;
      final num dmgB = (b['total_damage'] as num?) ?? 0;
      return dmgB.compareTo(dmgA);
    });

    final String bossName = (data['boss_name'] ?? 'BOSS DU DONJON').toString().toUpperCase();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.15),
            blurRadius: 25,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 56),
          const SizedBox(height: 10),
          const Text(
            "DONJON CONQUIS !",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "$bossName A ÉTÉ TERRASSÉ",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kSystemBlue,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "CLASSEMENT DU PODIUM :",
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (hunters.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                "Aucun score enregistré.",
                style: TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 12),
              ),
            )
          else
            ...List.generate(
              hunters.length > 5 ? 5 : hunters.length,
              (index) {
                final h = hunters[index];
                final String name = (h['name'] ?? 'Chasseur').toString();
                final int dmg = (h['total_damage'] as num?)?.toInt() ?? 0;
                final int squats = (h['squat_reps'] as num?)?.toInt() ?? 0;
                final int pushups = (h['pushup_reps'] as num?)?.toInt() ?? 0;
                final int abs = (h['abs_reps'] as num?)?.toInt() ?? 0;
                final bool isMe = (h['id'] == _hunterSessionId);

                Color rankColor = Colors.white70;
                String medal = "#${index + 1}";
                if (index == 0) {
                  rankColor = const Color(0xFFFFD700);
                  medal = "🥇 1ER";
                } else if (index == 1) {
                  rankColor = const Color(0xFFC0C0C0);
                  medal = "🥈 2E";
                } else if (index == 2) {
                  rankColor = const Color(0xFFCD7F32);
                  medal = "🥉 3E";
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? kSystemBlue.withOpacity(0.12) : Colors.black38,
                    border: Border.all(
                      color: isMe ? kSystemBlue : rankColor.withOpacity(0.5),
                      width: isMe ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$medal  ${name.toUpperCase()}${isMe ? ' (VOUS)' : ''}",
                              style: TextStyle(
                                color: rankColor,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "Squats: $squats | Pompes: $pushups | Abdos: $abs",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "$dmg PV",
                        style: const TextStyle(
                          color: Color(0xFF00FF66),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 44),
          const Divider(color: Colors.white24, thickness: 1),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF08182B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
            ),
            child: Column(
              children: [
                const Text(
                  "TÉLÉCHARGER L'APPLICATION SHADOWBURN",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF00FF66),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Poursuivez votre éveil en Solo, débloquez les Portails et devenez Monarque :",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: kAppDownloadUrl,
                    version: QrVersions.auto,
                    size: 165.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00FF66),
                    side: const BorderSide(color: Color(0xFF00FF66)),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(kAppDownloadUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text(
                    "ACCÉDER DIRECTEMENT À L'APPLICATION",
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF2E56),
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _leaveRaid,
              icon: const Icon(Icons.exit_to_app, size: 18),
              label: const Text(
                "QUITTER LA SALLE DE RAID",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exerciseButton({
    required String label,
    required String category,
    required Color color,
    required bool isEnabled,
  }) {
    final bool isAntiCheatLocked = (_antiCheatCooldownSeconds > 0);
    final bool canPress = isEnabled && !isAntiCheatLocked;

    final bool isTargetFor150 = (_comboStep == 1);
    final bool isTargetFor200 = (_comboStep == 2);
    final bool hasButtonGlow = (isTargetFor150 || isTargetFor200) && canPress;

    String gainText = "+25 PV";
    if (isTargetFor150) {
      gainText = "ENCHAÎNEZ ! (+150 PV FRÉNÉSIE)";
    } else if (isTargetFor200) {
      gainText = "BURST ULTIME ! (+200 PV CRITIQUE)";
    }

    if (isAntiCheatLocked) {
      gainText = "COOLDOWN ANTI-SPAM (${_antiCheatCooldownSeconds}s)";
    }

    final Color glowColor = isTargetFor200 ? const Color(0xFFFFD700) : const Color(0xFFFF2E56);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          side: BorderSide(
            color: canPress
                ? (hasButtonGlow ? glowColor : color)
                : Colors.white12,
            width: hasButtonGlow ? 2.5 : 1.5,
          ),
          backgroundColor: hasButtonGlow
              ? glowColor.withOpacity(0.25)
              : (canPress ? color.withOpacity(0.08) : Colors.black26),
        ),
        onPressed: canPress ? () => _handleExerciseTap(category, label) : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: canPress ? Colors.white : Colors.white30,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  isEnabled ? gainText : "VERROUILLÉ",
                  style: TextStyle(
                    color: canPress
                        ? (hasButtonGlow ? glowColor : color)
                        : Colors.white24,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            Icon(
              hasButtonGlow ? Icons.whatshot : Icons.fitness_center,
              color: canPress
                  ? (hasButtonGlow ? glowColor : color)
                  : Colors.white24,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
