// lib/services/quota_guard_service.dart

import 'package:shared_preferences/shared_preferences.dart';

class QuotaGuardService {
  static const String _kKeyDate = 'quota_date';
  static const String _kKeyWrites = 'quota_writes_count';
  
  // Seuil de sécurité préventif (blocage à 19 900 pour laisser une marge avant la limite stricte de 20 000)
  static const int kMaxSafeWrites = 19900;

  /// Vérifie si on a le droit d'écrire et incrémente le compteur journalier.
  /// Retourne `true` si l'écriture est autorisée, `false` si le seuil de sécurité est atteint.
  static Future<bool> checkAndIncrementWrite() async {
    final prefs = await SharedPreferences.getInstance();
    
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    
    final savedDate = prefs.getString(_kKeyDate) ?? '';
    int currentWrites = prefs.getInt(_kKeyWrites) ?? 0;

    // Si on change de jour, réinitialisation automatique du compteur
    if (savedDate != todayStr) {
      await prefs.setString(_kKeyDate, todayStr);
      await prefs.setInt(_kKeyWrites, 0);
      currentWrites = 0;
    }

    // Si le seuil critique est atteint, on bloque l'écriture préventivement
    if (currentWrites >= kMaxSafeWrites) {
      return false; 
    }

    // Incrémentation et sauvegarde locale
    currentWrites++;
    await prefs.setInt(_kKeyWrites, currentWrites);
    return true;
  }

  /// Permet de consulter le nombre d'écritures consommées aujourd'hui
  static Future<int> getTodayWritesCount() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    final savedDate = prefs.getString(_kKeyDate) ?? '';
    
    if (savedDate != todayStr) return 0;
    return prefs.getInt(_kKeyWrites) ?? 0;
  }
}