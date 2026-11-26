// lib/services/storage_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/balance.dart';
import '../core/json_utils.dart';
import '../core/log.dart';
import 'legacy_migration.dart';

typedef JsonMap = Map<String, dynamic>;

class LoadedSave {
  final JsonMap data;
  final String source;
  const LoadedSave(this.data, this.source);
}

class StorageService {
  static const String _mainKey = 'save_v3';
  static const String keyGodModeSave = 'save_godmode';
  static const List<String> _backupKeys = ['save_v3_bak1', 'save_v3_bak2', 'save_v3_bak3'];
  static const String _backupStampKey = 'save_v3_bak_stamp';
  static const Duration _backupEvery = Duration(hours: 6);

  static const String keyPenaltyActive = 'cerberus_penalty_active';
  static const String keyPenaltySquatsDone = 'cerberus_penalty_squats_done';
  static const String keyPenaltySquatsGoal = 'cerberus_penalty_squats_goal';
  static const String keySandboxVolatile = 'cerberus_sandbox_volatile';

  static bool blockAllRealSaves = false;

  static Future<void> _chain = Future<void>.value();

  static Future<void> saveGodMode(JsonMap data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyGodModeSave, jsonEncode(data));
      await prefs.reload();
    } catch (e) {
      dlog("Erreur saveGodMode : $e");
    }
  }

  static Future<JsonMap?> loadGodMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(keyGodModeSave);
      if (raw == null || raw.isEmpty) return null;
      final dynamic d = jsonDecode(raw);
      return d is Map ? JsonMap.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteGodModeSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyGodModeSave);
      await prefs.reload();
    } catch (e) {
      dlog("Erreur deleteGodModeSave : $e");
    }
  }

  static Future<void> writeSandboxVolatileState(bool isVolatile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keySandboxVolatile, isVolatile);
      await prefs.reload();
    } catch (e) {
      dlog("Erreur writeSandboxVolatileState : $e");
    }
  }

  static Future<bool> isSandboxVolatile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keySandboxVolatile) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> writePenaltyState({
    required bool active,
    required int squatsDone,
    required int squatsGoal,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyPenaltyActive, active);
      await prefs.setInt(keyPenaltySquatsDone, squatsDone);
      await prefs.setInt(keyPenaltySquatsGoal, squatsGoal);
      await prefs.reload();
    } catch (e) {
      dlog("Erreur writePenaltyState : $e");
    }
  }

  static Future<JsonMap> readPenaltyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return <String, dynamic>{
        'active': prefs.getBool(keyPenaltyActive) ?? false,
        'squatsDone': prefs.getInt(keyPenaltySquatsDone) ?? 0,
        'squatsGoal': prefs.getInt(keyPenaltySquatsGoal) ?? 100,
      };
    } catch (e) {
      dlog("Erreur readPenaltyState : $e");
      return <String, dynamic>{'active': false, 'squatsDone': 0, 'squatsGoal': 100};
    }
  }

  static Future<LoadedSave?> load() async {
    final prefs = await SharedPreferences.getInstance();

    final main = _decode(prefs.getString(_mainKey));
    if (main != null) return LoadedSave(main, 'main');

    for (int i = 0; i < _backupKeys.length; i++) {
      final b = _decode(prefs.getString(_backupKeys[i]));
      if (b != null) return LoadedSave(b, 'backup${i + 1}');
    }

    final legacy = LegacyMigration.fromV2(prefs);
    if (legacy != null) return LoadedSave(legacy, 'legacy');
    return null;
  }

  static Future<void> save(JsonMap data) {
    if (blockAllRealSaves) {
      return Future<void>.value();
    }

    final String json = jsonEncode(data);
    _chain = _chain.then((_) => _write(json)).catchError((Object e) {
      dlog("Erreur de sauvegarde : $e");
    });
    return _chain;
  }

  static Future<void> forceSaveDirect(JsonMap data) {
    final String json = jsonEncode(data);
    _chain = _chain.then((_) => _write(json)).catchError((Object e) {
      dlog("Erreur forceSaveDirect : $e");
    });
    return _chain;
  }

  static Future<void> backupNow() {
    if (blockAllRealSaves) return Future<void>.value();
    _chain = _chain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final String? previous = prefs.getString(_mainKey);
      if (previous != null && _decode(previous) != null) {
        await _rotate(prefs, previous);
      }
    }).catchError((Object e) {
      dlog("Erreur de copie de secours : $e");
    });
    return _chain;
  }

  static Future<void> _write(String json) async {
    final prefs = await SharedPreferences.getInstance();
    if (_backupDue(prefs)) {
      final String? previous = prefs.getString(_mainKey);
      if (previous != null && _decode(previous) != null) {
        await _rotate(prefs, previous);
      }
    }
    await prefs.setString(_mainKey, json);
  }

  static bool _backupDue(SharedPreferences prefs) {
    final String? stamp = prefs.getString(_backupStampKey);
    if (stamp == null) return true;
    final DateTime? last = DateTime.tryParse(stamp);
    if (last == null) return true;
    return DateTime.now().difference(last) >= _backupEvery;
  }

  static Future<void> _rotate(SharedPreferences prefs, String previous) async {
    final String? b1 = prefs.getString(_backupKeys[0]);
    final String? b2 = prefs.getString(_backupKeys[1]);
    if (b2 != null) await prefs.setString(_backupKeys[2], b2);
    if (b1 != null) await prefs.setString(_backupKeys[1], b1);
    await prefs.setString(_backupKeys[0], previous);
    await prefs.setString(_backupStampKey, DateTime.now().toIso8601String());
  }

  static JsonMap? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final dynamic d = jsonDecode(raw);
      if (d is! Map) return null;
      final m = JsonMap.from(d);
      if (m['v'] is! num) return null;
      if (!Balance.order.contains(asString(m['rank']))) return null;
      final double xp = asDouble(m['xp'], double.nan);
      if (xp.isNaN || xp.isInfinite) return null;
      return m;
    } catch (_) {
      return null;
    }
  }
}