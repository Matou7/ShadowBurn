// lib/services/raid_admin_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'lan_socket_service.dart';
import 'quota_guard_service.dart';

class RaidAdminService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final LanSocketService _lanSocket = LanSocketService();

  static const Duration _kTimeout = Duration(seconds: 8);
  static const int _kAdminLeaseMs = 600000;

  static const int _kMinHp = 1;
  static const int _kMaxHp = 500000;
  static const int _kMaxDamage = 50000;
  static const int _kMaxMinutes = 1440;

  static String? _activeLanWsUrl;
  static String? _activeLanRoomId;
  static String? _activeLanAdminKey;

  static const raidPresets = [
    {'hp': 5000, 'label': 'RAID STANDARD (5 000 PV)'},
    {'hp': 15000, 'label': 'RAID ÉLITE (15 000 PV)'},
    {'hp': 30000, 'label': 'RAID MONARQUE (30 000 PV)'},
  ];

  static bool get isLanActive =>
      _activeLanWsUrl != null && _activeLanWsUrl!.trim().isNotEmpty;

  static void configureLan({
    required String wsUrl,
    required String roomId,
    String? adminKey,
  }) {
    final cleanUrl = wsUrl.trim();
    if (cleanUrl.isEmpty) {
      _activeLanWsUrl = null;
      _activeLanRoomId = null;
      _activeLanAdminKey = null;
      return;
    }

    _activeLanWsUrl = cleanUrl;
    _activeLanRoomId = roomId.trim().isEmpty ? 'LAN_1' : roomId.trim();
    if (adminKey != null) {
      _activeLanAdminKey = adminKey.trim();
    }
  }

  static Future<void> clearLan() async {
    _activeLanWsUrl = null;
    _activeLanRoomId = null;
    _activeLanAdminKey = null;

    try {
      await _lanSocket.disconnect();
    } catch (e) {
      debugPrint('[RAID ADMIN LAN] Déconnexion : $e');
    }
  }

  static bool _validRoomId(String roomId) {
    final value = roomId.trim();
    return value.isNotEmpty && value.length <= 80;
  }

  static bool _validHp(int hp) => hp >= _kMinHp && hp <= _kMaxHp;

  static bool _validDamage(int damage) => damage > 0 && damage <= _kMaxDamage;

  static bool _validNonZeroMinutes(int minutes) =>
      minutes != 0 && minutes.abs() <= _kMaxMinutes;

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  static List _resetHunters(dynamic rawHunters) {
    final result = [];
    if (rawHunters is! Iterable) return result;

    final now = DateTime.now().millisecondsSinceEpoch;

    for (final hunter in rawHunters) {
      final copy = _asMap(hunter);
      if (copy == null) continue;

      copy['total_damage'] = 0;
      copy['squat_reps'] = 0;
      copy['pushup_reps'] = 0;
      copy['abs_reps'] = 0;
      copy['combo_step'] = 0;
      copy['last_seen'] = now;

      result.add(copy);
    }

    return result;
  }

  static Future<bool> _canWriteQuota({
    bool critical = false,
  }) async {
    try {
      final used = await QuotaGuardService.getTodayWrites();
      if (used >= QuotaGuardService.dailyWriteLimit) {
        return false;
      }
      if (!critical && used >= QuotaGuardService.softBlockThreshold) {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[RAID ADMIN] Lecture quota impossible : $e');
      return false;
    }
  }

  static Future<void> _recordQuotaWrite({
    bool critical = false,
  }) async {
    try {
      await QuotaGuardService.checkAndIncrementWrite(
        isCriticalClosure: critical,
      );
    } catch (_) {}
  }

  static Future<String?> _sendLanAdminCommand(
    String roomId,
    Map<String, dynamic> payload,
  ) async {
    final wsUrl = (_activeLanWsUrl ?? '').trim();
    final targetRoom = roomId.trim().isNotEmpty
        ? roomId.trim()
        : (_activeLanRoomId ?? 'LAN_1');

    if (wsUrl.isEmpty) {
      return 'URL WebSocket LAN non configurée.';
    }

    if (!_validRoomId(targetRoom)) {
      return 'Identifiant de salle LAN invalide.';
    }

    try {
      if (!_lanSocket.isConnected) {
        final connected = await _lanSocket.connect(wsUrl);
        if (!connected) {
          return 'Connexion WebSocket LAN impossible sur $wsUrl.';
        }
      }

      final Map<String, dynamic> authFields =
          (_activeLanAdminKey != null && _activeLanAdminKey!.isNotEmpty)
              ? {'adminKey': _activeLanAdminKey}
              : <String, dynamic>{};

      _lanSocket.sendJson({
        'type': 'join',
        'role': 'admin',
        'room': targetRoom,
        'roomId': targetRoom,
        'name': 'Admin_LAN',
        ...authFields,
      });

      _lanSocket.sendJson({
        'type': 'admin',
        'role': 'admin',
        'room': targetRoom,
        'roomId': targetRoom,
        ...authFields,
        ...payload,
      });

      return null;
    } catch (e) {
      debugPrint('[RAID ADMIN LAN] Erreur commande : $e');
      return 'Erreur LAN : $e';
    }
  }

  static Map<String, dynamic> _adminActivityStamp() {
    final now = DateTime.now().millisecondsSinceEpoch;

    return {
      'last_activity_ms': now,
      'admin_last_seen_ms': now,
      'lease_expires_at': now + _kAdminLeaseMs,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  static Future<String?> _runTransaction(
    String roomId, {
    bool critical = false,
    required Future<void> Function(
      Transaction transaction,
      dynamic docRef,
      Map<String, dynamic> data,
    ) action,
  }) async {
    if (!_validRoomId(roomId)) {
      return 'Identifiant de salle invalide.';
    }

    if (!await _canWriteQuota(critical: critical)) {
      return critical
          ? 'Quota journalier atteint.'
          : 'Quota journalier atteint (19 500 écritures).';
    }

    try {
      final docRef = _firestore.collection('current_raids').doc(roomId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          throw StateError('Salle [$roomId] introuvable.');
        }

        final rawData = snapshot.data();
        final Map<String, dynamic> data = rawData != null
            ? Map<String, dynamic>.of(rawData)
            : <String, dynamic>{};
        await action(transaction, docRef, data);
      }).timeout(_kTimeout);

      await _recordQuotaWrite(critical: critical);
      return null;
    } on StateError catch (e) {
      return e.message;
    } on FirebaseException catch (e) {
      debugPrint('[RAID ADMIN] Firebase ${e.code} : ${e.message}');
      return 'Erreur Firebase : ${e.message ?? e.code}';
    } catch (e) {
      debugPrint('[RAID ADMIN] Transaction : $e');
      return 'Erreur : $e';
    }
  }

  static Future<String?> applyPreset(
    int maxHp,
    String label, {
    required String roomId,
  }) async {
    if (!_validHp(maxHp)) {
      return 'Valeur de PV invalide.';
    }

    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty || cleanLabel.length > 80) {
      return 'Nom de preset invalide.';
    }

    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': 'set_preset',
        'maxHp': maxHp,
        'label': cleanLabel,
      });
    }

    return _runTransaction(
      roomId,
      action: (transaction, docRef, data) async {
        final currentStatus = (data['status'] ?? 'waiting').toString();
        final nextStatus =
            (currentStatus == 'victory' || currentStatus == 'failed')
                ? 'waiting'
                : currentStatus;

        transaction.update(docRef, {
          'max_hp': maxHp,
          'current_hp': maxHp,
          'boss_name': cleanLabel,
          'preset_label': cleanLabel,
          'logs': <dynamic>[],
          'hunters': _resetHunters(data['hunters']),
          'status': nextStatus,
          ..._adminActivityStamp(),
        });
      },
    );
  }

  static Future<String?> strikeBoss(
    int damage, {
    required String roomId,
  }) async {
    if (!_validDamage(damage)) {
      return 'Dégâts invalides.';
    }

    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': 'strike_boss',
        'damage': damage,
      });
    }

    return _runTransaction(
      roomId,
      action: (transaction, docRef, data) async {
        final maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;
        final currentHp = (data['current_hp'] as num?)?.toInt() ?? maxHp;

        if (!_validHp(maxHp) || currentHp < 0 || currentHp > maxHp) {
          throw StateError('État des PV invalide.');
        }

        final nextHp = (currentHp - damage).clamp(0, maxHp);
        final updates = <String, dynamic>{
          'current_hp': nextHp,
          'last_strike_at': FieldValue.serverTimestamp(),
          ..._adminActivityStamp(),
        };

        if (nextHp == 0) {
          updates['status'] = 'victory';
        }

        transaction.update(docRef, updates);
      },
    );
  }

  static Future<String?> resetBoss({required String roomId}) async {
    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': 'reset_boss',
      });
    }

    return _runTransaction(
      roomId,
      action: (transaction, docRef, data) async {
        final maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;

        if (!_validHp(maxHp)) {
          throw StateError('PV maximum invalide.');
        }

        transaction.update(docRef, {
          'current_hp': maxHp,
          'status': 'active',
          'logs': <dynamic>[],
          'hunters': _resetHunters(data['hunters']),
          ..._adminActivityStamp(),
        });
      },
    );
  }

  static Future<String?> setRaidStatus(
    String status, {
    required String roomId,
  }) async {
    const allowedStatuses = {
      'waiting',
      'active',
      'paused',
      'failed',
      'victory',
      'finished',
      'abandoned',
      'closed',
    };

    if (!allowedStatuses.contains(status)) {
      return 'Statut de raid non autorisé.';
    }

    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': status == 'active' ? 'start' : status,
        'status': status,
      });
    }

    return _runTransaction(
      roomId,
      action: (transaction, docRef, data) async {
        final updates = <String, dynamic>{
          'status': status,
          ..._adminActivityStamp(),
        };

        if (status == 'waiting') {
          final maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;

          if (!_validHp(maxHp)) {
            throw StateError('PV maximum invalide.');
          }

          updates['logs'] = <dynamic>[];
          updates['current_hp'] = maxHp;
        }

        transaction.update(docRef, updates);
      },
    );
  }

  static Future<String?> _changeRaidMinutes(
    int minutes, {
    required String roomId,
  }) async {
    if (!_validNonZeroMinutes(minutes)) {
      return 'Durée invalide.';
    }

    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': 'add_minutes',
        'minutes': minutes,
      });
    }

    return _runTransaction(
      roomId,
      action: (transaction, docRef, data) async {
        final currentEndMs = (data['target_end_time'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;

        final now = DateTime.now().millisecondsSinceEpoch;
        final baseMs = currentEndMs < now ? now : currentEndMs;

        final newEndMs = baseMs + Duration(minutes: minutes).inMilliseconds;

        if (newEndMs < now - const Duration(days: 1).inMilliseconds ||
            newEndMs > now + const Duration(days: 7).inMilliseconds) {
          throw StateError('Nouvelle échéance hors limites.');
        }

        transaction.update(docRef, {
          'target_end_time': newEndMs,
          ..._adminActivityStamp(),
        });
      },
    );
  }

  static Future<String?> extendRaidMinutes(
    int minutes, {
    required String roomId,
  }) async {
    if (minutes <= 0) return 'La durée doit être positive.';
    return _changeRaidMinutes(minutes, roomId: roomId);
  }

  static Future<String?> reduceRaidMinutes(
    int minutes, {
    required String roomId,
  }) async {
    if (minutes <= 0) return 'La durée doit être positive.';
    return _changeRaidMinutes(-minutes, roomId: roomId);
  }

  static Future<String?> resetToMidnight({required String roomId}) async {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, 23, 58);

    if (target.isBefore(now)) {
      return 'L’heure de réinitialisation est déjà passée.';
    }

    final minutes = target.difference(now).inMinutes.clamp(1, _kMaxMinutes);

    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': 'add_minutes',
        'minutes': minutes,
      });
    }

    return _runTransaction(
      roomId,
      action: (transaction, docRef, data) async {
        transaction.update(docRef, {
          'target_end_time': target.millisecondsSinceEpoch,
          'status': 'active',
          ..._adminActivityStamp(),
        });
      },
    );
  }

  static Future<String?> expireRaidNow({required String roomId}) async {
    if (isLanActive) {
      return _sendLanAdminCommand(roomId, {
        'command': 'expire_now',
      });
    }

    return _runTransaction(
      roomId,
      critical: true,
      action: (transaction, docRef, data) async {
        transaction.update(docRef, {
          'target_end_time': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          'status': 'failed',
          ..._adminActivityStamp(),
        });
      },
    );
  }
}