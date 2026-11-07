// lib/services/raid_admin_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'quota_guard_service.dart';

class RaidAdminService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List raidPresets = [
    {'hp': 5000, 'label': 'RAID STANDARD (5 000 PV)'},
  ];

  static Future applyPreset(int maxHp, String label, {required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        debugPrint("[QUOTA GUARD] Seuil atteint. applyPreset bloqué.");
        return;
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snap = await docRef.get();
      final List resetHunters = [];

      if (snap.exists) {
        final Map data = snap.data() ?? {};
        final dynamic rawHunters = data['hunters'];
        if (rawHunters is Iterable) {
          for (final h in rawHunters) {
            if (h is Map) {
              final Map copy = Map.from(h);
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
      }

      await docRef.set({
        'max_hp': 5000,
        'current_hp': 5000,
        'boss_name': 'RAID STANDARD (5 000 PV)',
        'preset_label': 'RAID STANDARD (5 000 PV)',
        'logs': [],
        'hunters': resetHunters,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur applyPreset: $e");
    }
  }

  static Future strikeBoss(int damage, {required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        debugPrint("[QUOTA GUARD] Seuil atteint. strikeBoss bloqué.");
        return;
      }

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snap = await docRef.get();
      if (!snap.exists) return;

      final Map data = snap.data() ?? {};
      final int currentHp = (data['current_hp'] as num?)?.toInt() ?? 5000;
      final int nextHp = (currentHp - damage).clamp(0, 5000);

      final Map<String, dynamic> updates = {
        'current_hp': nextHp,
        'last_strike_at': FieldValue.serverTimestamp(),
      };
      if (nextHp <= 0) {
        updates['status'] = 'victory';
      }
      await docRef.update(updates);
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur strikeBoss: $e");
    }
  }

  static Future resetBoss({required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snap = await docRef.get();
      if (!snap.exists) return;

      final Map data = snap.data() ?? {};
      final dynamic rawHunters = data['hunters'];
      final List resetHunters = [];

      if (rawHunters is Iterable) {
        for (final h in rawHunters) {
          if (h is Map) {
            final Map copy = Map.from(h);
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
        'current_hp': 5000,
        'max_hp': 5000,
        'preset_label': 'RAID STANDARD (5 000 PV)',
        'status': 'active',
        'logs': [],
        'hunters': resetHunters,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur resetBoss: $e");
    }
  }

  static Future setRaidStatus(String status, {required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final Map<String, dynamic> payload = {
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (status == 'waiting') {
        payload['logs'] = [];
        payload['current_hp'] = 5000;
        payload['max_hp'] = 5000;
      }
      await docRef.update(payload);
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur setRaidStatus: $e");
    }
  }

  static Future extendRaidMinutes(int minutes, {required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;

      final Map data = snapshot.data() ?? {};
      final int currentEndMs = (data['target_end_time'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      DateTime baseTime = DateTime.fromMillisecondsSinceEpoch(currentEndMs);
      if (baseTime.isBefore(DateTime.now())) {
        baseTime = DateTime.now();
      }

      final newEndTime = baseTime.add(Duration(minutes: minutes));
      await docRef.update({
        'target_end_time': newEndTime.millisecondsSinceEpoch,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur extendRaidMinutes: $e");
    }
  }

  static Future reduceRaidMinutes(int minutes, {required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final docRef = _firestore.collection('current_raids').doc(roomId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;

      final Map data = snapshot.data() ?? {};
      final int currentEndMs = (data['target_end_time'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      final DateTime baseTime = DateTime.fromMillisecondsSinceEpoch(currentEndMs);
      final newEndTime = baseTime.subtract(Duration(minutes: minutes));

      await docRef.update({
        'target_end_time': newEndTime.millisecondsSinceEpoch,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur reduceRaidMinutes: $e");
    }
  }

  static Future resetToMidnight({required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 23, 58, 0);
      final docRef = _firestore.collection('current_raids').doc(roomId);

      await docRef.update({
        'target_end_time': midnight.millisecondsSinceEpoch,
        'status': 'active',
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur resetToMidnight: $e");
    }
  }

  static Future expireRaidNow({required String roomId}) async {
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final docRef = _firestore.collection('current_raids').doc(roomId);
      await docRef.update({
        'target_end_time': DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
        'status': 'failed',
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("[RAID ADMIN] Erreur expireRaidNow: $e");
    }
  }
}