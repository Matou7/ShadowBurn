// lib/services/sandbox_manager.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SandboxManager {
  static const String keyGodSave = 'save_godmode';
  static bool isSandboxActive = false;
  static bool persistPenalty = false;

  /// Active le God Mode (strictement interdit en release)
  static void enterSandbox() {
    if (!kDebugMode) return;
    isSandboxActive = true;
    persistPenalty = false;
    StorageService.blockAllRealSaves = true;
  }

  /// Quitte le God Mode et nettoie tout le sas
  static Future<void> exitSandbox({bool keepChanges = false, Map<String, dynamic>? currentData}) async {
    isSandboxActive = false;
    persistPenalty = false;
    StorageService.blockAllRealSaves = false;

    await deleteSandboxFile();
    await clearNativePenalty();

    if (keepChanges && currentData != null && kDebugMode) {
      await StorageService.forceSaveDirect(currentData);
    }
  }

  /// Sauvegarde du bac à sable (UNIQUEMENT en mode debug et si la persistance est cochée)
  static Future<void> saveSandbox(Map<String, dynamic> data) async {
    if (!kDebugMode || !isSandboxActive || !persistPenalty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyGodSave, jsonEncode(data));
      await prefs.reload();
    } catch (_) {}
  }

  /// Chargement du bac à sable au boot (ignoré en release)
  static Future?> loadSandbox() async {
    if (!kDebugMode) {
      await deleteSandboxFile();
      return null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(keyGodSave);
      if (raw == null || raw.isEmpty) return null;
      final dynamic d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// Supprime le fichier de sauvegarde du God Mode
  static Future<void> deleteSandboxFile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyGodSave);
      await prefs.reload();
    } catch (_) {}
  }

  /// Force la purge des clés natives Android
  static Future<void> clearNativePenalty() async {
    await StorageService.writePenaltyState(
      active: false,
      squatsDone: 0,
      squatsGoal: 100,
    );
    try {
      await LockService.unlockScreen(force: true);
    } catch (_) {}
  }
}
