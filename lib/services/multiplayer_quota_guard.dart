import 'package:shared_preferences/shared_preferences.dart';

/// Local circuit breaker for each browser/device.
/// It does not claim to read Firebase's live quota; it prevents repeated
/// retries on this device after Firestore has explicitly rejected a request.
class MultiplayerQuotaGuard {
  static const String _lockUntilKey = 'shadowburn_multiplayer_quota_lock_until';

  static Future<bool> isPaused() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? untilMs = prefs.getInt(_lockUntilKey);
      if (untilMs == null) return false;
      if (DateTime.now().millisecondsSinceEpoch < untilMs) return true;
      await prefs.remove(_lockUntilKey);
      return false;
    } catch (_) {
      // If local storage is unavailable, fail open rather than permanently
      // blocking multiplayer for a storage error.
      return false;
    }
  }

  static Future<void> pauseUntilSafeRetry() async {
    try {
      final now = DateTime.now();
      DateTime retryAt = DateTime(now.year, now.month, now.day, 10);
      if (!retryAt.isAfter(now)) {
        retryAt = retryAt.add(const Duration(days: 1));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lockUntilKey, retryAt.millisecondsSinceEpoch);
    } catch (_) {}
  }
}
