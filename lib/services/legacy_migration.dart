// lib/services_legacy_migration.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/balance.dart';
import '../core/json_utils.dart';
import '../core/log.dart';

/// Lit l'ancienne sauvegarde V2 (clés séparées) et la convertit au nouveau format.
/// IMPORTANT : on ne supprime JAMAIS les anciennes clés. Elles restent comme filet de sécurité.
class LegacyMigration {
  static Map<String, dynamic>? fromV2(SharedPreferences prefs) {
    if (!prefs.containsKey('rank') && !prefs.containsKey('xp')) return null;
    try {
      // --- Nom du joueur (même logique que la V2) ---
      final String? saved = prefs.getString('player_name_v2');
      final String? backup = prefs.getString('username');
      String name;
      if (saved == "Chasseur" && backup != null && backup != "Chasseur" && backup != "JIN-WOO") {
        name = backup;
      } else if (saved == null || saved.isEmpty || saved == "JIN-WOO" || saved == "Chargement...") {
        name = (backup != null && backup.isNotEmpty && backup != "JIN-WOO") ? backup : "Chasseur";
      } else {
        name = saved;
      }

      String rank = prefs.getString('rank') ?? "E";
      if (!Balance.order.contains(rank)) rank = "E";

      Map<String, dynamic> keys = {"E": 0, "D": 0, "C": 0, "B": 0, "A": 0, "S": 0, "NATION": 0};
      final String? inv = prefs.getString('inventoryKeys');
      if (inv != null) {
        final decoded = asMap(jsonDecode(inv));
        decoded.forEach((k, v) => keys[k] = asInt(v));
      }

      Map<String, dynamic> calendar = {};
      final String? cal = prefs.getString('calendarHistory');
      if (cal != null) calendar = asMap(jsonDecode(cal));

      List<dynamic> history = [];
      final String? hist = prefs.getString('saveHistory');
      if (hist != null) history = asList(jsonDecode(hist));

      Map<String, dynamic>? dungeon;
      final String? dun = prefs.getString('activeDungeon');
      if (dun != null) dungeon = asMap(jsonDecode(dun));

      final String? lastReset = prefs.getString('lastResetDate');
      final String? endStr = prefs.getString('classChangeEndTime');

      return {
        'v': 3,
        'savedAt': prefs.getString('lastSaveTime') ?? DateTime.now().toIso8601String(),
        'username': name,
        'rank': rank,
        'xp': asDouble(prefs.get('xp')),
        'coins': asInt(prefs.get('coins')),
        'hp': asInt(prefs.get('hp'), 100),
        'maxHp': asInt(prefs.get('maxHp'), 100),
        'streak': asInt(prefs.get('streak')),
        'lastResetDate': (lastReset == null || lastReset.isEmpty) ? null : lastReset,
        'keys': keys,
        'unlockedTitles': ["Nouveau Chasseur"],
        'equippedTitle': "Nouveau Chasseur",
        'pompes': asInt(prefs.get('dailyPompes')),
        'abdos': asInt(prefs.get('dailyAbdos')),
        'squats': asInt(prefs.get('dailySquats')),
        'steps': asInt(prefs.get('dailySteps')),
        'sessionKm': asDouble(prefs.get('sessionKm')),
        'kmConsumed': asDouble(prefs.get('kmConsumedByDaily')),
        'cycles': asInt(prefs.get('dailyCyclesCompleted')),
        'recordBrokenToday': false,
        'isTracking': false,
        'totalPompes': asInt(prefs.get('totalPompes')),
        'totalAbdos': asInt(prefs.get('totalAbdos')),
        'totalSquats': asInt(prefs.get('totalSquats')),
        'totalKm': asDouble(prefs.get('totalKm')),
        'totalSurpassement': asInt(prefs.get('totalSurpassement')),
        'dungeonsCompleted': asInt(prefs.get('dungeonsCompleted')),
        'maxPompes': asInt(prefs.get('maxPompes')),
        'maxAbdos': asInt(prefs.get('maxAbdos')),
        'maxSquats': asInt(prefs.get('maxSquats')),
        'maxKm': asDouble(prefs.get('maxKm')),
        'penaltyActive': asBool(prefs.get('isInPenaltyZone')),
        'penaltySquats': asInt(prefs.get('penaltySquatsDone')),
        'cc': {
          'started': endStr != null,
          'end': endStr,
          'p': asInt(prefs.get('classChangePompes')),
          'a': asInt(prefs.get('classChangeAbdos')),
          's': asInt(prefs.get('classChangeSquats')),
          'k': asDouble(prefs.get('classChangeKm')),
        },
        'calendar': calendar,
        'saveHistory': history,
        'dungeon': dungeon,
        'dungeonRed': asBool(prefs.get('isActiveDungeonRed')),
        'threats': <dynamic>[],
        'urgent': null,
        'surpassQuest': false,
        'adminPassword': prefs.getString('admin_password') ?? "SOLO",
        'stepBaseline': null,
      };
    } catch (e) {
      dlog("Migration V2 impossible : $e");
      return null;
    }
  }
}
