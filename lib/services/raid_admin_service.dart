// lib/services/raid_admin_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'quota_guard_service.dart';

class RaidAdminService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _kTimeout = Duration(seconds: 6);
  static const int _kAdminLeaseMs = 600000; // 10 minutes

  static const List> raidPresets = [
    {'hp': 5000, 'label': 'RAID STANDARD (5 000 PV)'},
    {'hp': 15000, 'label': 'RAID ÉLITE (15 000 PV)'},
    {'hp': 30000, 'label': 'RAID MONARQUE (30 000 PV)'},
  ];

  static Map<String, dynamic> _adminActivityStamp() {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    return {
      'last_activity_ms': nowMs,
      'admin_last_seen_ms': nowMs,
      'lease_expires_at': nowMs + _kAdminLeaseMs,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  static Future<String?> applyPreset(
    int maxHp,
    String label, {
    required String roomId,
  }) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snap = await docRef.get().timeout(_kTimeout);
      if (!snap.exists) return "Salle [$roomId] introuvable.";

      final List> resetHunters = [];
      final Map<String, dynamic> data = snap.data() ?? {};
      final dynamic rawHunters = data['hunters'];
      if (rawHunters is Iterable) {
        for (final h in rawHunters) {
          if (h is Map) {
            final Map<String, dynamic> copy = Map<String, dynamic>.from(h);
            copy['total_damage'] = 0;
            copy['squat_reps'] = 0;
            copy['pushup_reps'] = 0;
            copy['abs_reps'] = 0;
            copy['combo_step'] = 0;
            copy['last_seen'] = DateTime.now().millisecondsSinceEpoch;
            resetHunters.add(copy);
          }
        }
      }

      await docRef.set({
        'max_hp': maxHp,
        'current_hp': maxHp,
        'boss_name': label,
        'preset_label': label,
        'logs': [],
        'hunters': resetHunters,
        ..._adminActivityStamp(),
      }, SetOptions(merge: true)).timeout(_kTimeout);

      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur applyPreset: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> strikeBoss(
    int damage, {
    required String roomId,
  }) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snap = await docRef.get().timeout(_kTimeout);
      if (!snap.exists) return "Salle [$roomId] introuvable.";

      final Map<String, dynamic> data = snap.data() ?? {};
      final int maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;
      final int currentHp = (data['current_hp'] as num?)?.toInt() ?? maxHp;
      final int nextHp = (currentHp - damage).clamp(0, maxHp);

      final Map<String, dynamic> updates = {
        'current_hp': nextHp,
        'last_strike_at': FieldValue.serverTimestamp(),
        ..._adminActivityStamp(),
      };
      if (nextHp <= 0) {
        updates['status'] = 'victory';
      }
      await docRef.update(updates).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur strikeBoss: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> resetBoss({required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snap = await docRef.get().timeout(_kTimeout);
      if (!snap.exists) return "Salle [$roomId] introuvable.";

      final Map<String, dynamic> data = snap.data() ?? {};
      final int maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;
      final dynamic rawHunters = data['hunters'];
      final List> resetHunters = [];

      if (rawHunters is Iterable) {
        for (final h in rawHunters) {
          if (h is Map) {
            final Map<String, dynamic> copy = Map<String, dynamic>.from(h);
            copy['total_damage'] = 0;
            copy['squat_reps'] = 0;
            copy['pushup_reps'] = 0;
            copy['abs_reps'] = 0;
            copy['combo_step'] = 0;
            copy['last_seen'] = DateTime.now().millisecondsSinceEpoch;
            resetHunters.add(copy);
          }
        }
      }

      await docRef.update({
        'current_hp': maxHp,
        'max_hp': maxHp,
        'status': 'active',
        'logs': [],
        'hunters': resetHunters,
        ..._adminActivityStamp(),
      }).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur resetBoss: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> setRaidStatus(
    String status, {
    required String roomId,
  }) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final Map<String, dynamic> payload = {
        'status': status,
        ..._adminActivityStamp(),
      };
      if (status == 'waiting') {
        payload['logs'] = [];
        payload['current_hp'] = 5000;
        payload['max_hp'] = 5000;
      }
      await docRef.update(payload).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur setRaidStatus: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> extendRaidMinutes(
    int minutes, {
    required String roomId,
  }) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snapshot = await docRef.get().timeout(_kTimeout);
      if (!snapshot.exists) return "Salle [$roomId] introuvable.";

      final Map<String, dynamic> data = snapshot.data() ?? {};
      final int currentEndMs = (data['target_end_time'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      DateTime baseTime = DateTime.fromMillisecondsSinceEpoch(currentEndMs);
      if (baseTime.isBefore(DateTime.now())) {
        baseTime = DateTime.now();
      }

      final newEndTime = baseTime.add(Duration(minutes: minutes));
      await docRef.update({
        'target_end_time': newEndTime.millisecondsSinceEpoch,
        ..._adminActivityStamp(),
      }).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur extendRaidMinutes: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> reduceRaidMinutes(
    int minutes, {
    required String roomId,
  }) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snapshot = await docRef.get().timeout(_kTimeout);
      if (!snapshot.exists) return "Salle [$roomId] introuvable.";

      final Map<String, dynamic> data = snapshot.data() ?? {};
      final int currentEndMs = (data['target_end_time'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      final DateTime baseTime = DateTime.fromMillisecondsSinceEpoch(currentEndMs);
      final newEndTime = baseTime.subtract(Duration(minutes: minutes));

      await docRef.update({
        'target_end_time': newEndTime.millisecondsSinceEpoch,
        ..._adminActivityStamp(),
      }).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur reduceRaidMinutes: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> resetToMidnight({required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        return "Quota journalier atteint (19 500 écritures).";
      }

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 23, 58, 0);
      final docRef = _firestore.collection('current_raids').doc(roomId);

      await docRef.update({
        'target_end_time': midnight.millisecondsSinceEpoch,
        'status': 'active',
        ..._adminActivityStamp(),
      }).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur resetToMidnight: $e");
      return "Erreur : $e";
    }
  }

  static Future<String?> expireRaidNow({required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite(
        isCriticalClosure: true,
      );
      if (!canWrite) {
        return "Quota journalier atteint.";
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      await docRef.update({
        'target_end_time': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
        'status': 'failed',
        ..._adminActivityStamp(),
      }).timeout(_kTimeout);
      return null;
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur expireRaidNow: $e");
      return "Erreur : $e";
    }
  }
}