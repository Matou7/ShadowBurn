import 'package:flutter/foundation.dart';
import 'arena_backend_service.dart';

class RaidAdminService {
  static const List raidPresets = [
    {'hp': 5000, 'label': 'RAID STANDARD (5 000 PV)'},
  ];

  static Future<void> applyPreset(int maxHp, String label, {required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'applyPreset');

  static Future<void> strikeBoss(int damage, {required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'strikeBoss', damage: damage);

  static Future<void> resetBoss({required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'resetBoss');

  static Future<void> setRaidStatus(String status, {required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'setRaidStatus', status: status);

  static Future<void> extendRaidMinutes(int minutes, {required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'extendRaidMinutes', minutes: minutes);

  static Future<void> reduceRaidMinutes(int minutes, {required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'reduceRaidMinutes', minutes: minutes);

  static Future<void> resetToMidnight({required String roomId, required String adminKey}) {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, 23).millisecondsSinceEpoch;
    return _action(roomId, adminKey, 'resetToMidnight', targetEndTimeMs: target);
  }

  static Future<void> expireRaidNow({required String roomId, required String adminKey}) =>
      _action(roomId, adminKey, 'expireRaidNow');

  static Future<void> _action(
    String roomId,
    String adminKey,
    String action, {
    int? damage,
    int? minutes,
    String? status,
    int? targetEndTimeMs,
  }) async {
    try {
      await ArenaBackendService.adminAction(
        roomId: roomId,
        adminKey: adminKey,
        action: action,
        damage: damage,
        minutes: minutes,
        status: status,
        targetEndTimeMs: targetEndTimeMs,
      );
    } catch (error) {
      debugPrint('[RAID ADMIN] $action refusée : $error');
      rethrow;
    }
  }
}
