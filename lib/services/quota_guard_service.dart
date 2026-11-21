// lib/services/quota_guard_service.dart

import 'package:shared_preferences/shared_preferences.dart';

class QuotaGuardService {
  static const int dailyWriteLimit = 20000;
  static const int remainingWriteReserve = 500;
  static const int softBlockThreshold =
      dailyWriteLimit - remainingWriteReserve; // 19 500

  static String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'quota_writes_$y$m$d';
  }

  static Future<int> getTodayWrites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_todayKey()) ?? 0;
  }

  static Future<int> getRemainingWrites() async {
    final used = await getTodayWrites();
    final rem = dailyWriteLimit - used;
    return rem > 0 ? rem : 0;
  }

  static Future<bool> isReserveReached() async {
    final used = await getTodayWrites();
    return used >= softBlockThreshold;
  }

  /// Autorise les écritures courantes tant qu'il reste plus de 500 écritures.
  /// Réserve les 500 dernières écritures aux clôtures critiques (victoire boss).
  static Future<bool> checkAndIncrementWrite({
    bool isCriticalClosure = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _todayKey();
    final current = prefs.getInt(key) ?? 0;

    if (!isCriticalClosure && current >= softBlockThreshold) {
      return false;
    }

    if (current >= dailyWriteLimit) {
      return false;
    }

    await prefs.setInt(key, current + 1);
    return true;
  }
}