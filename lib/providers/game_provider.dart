// lib/providers/game_provider.dart
import '../services/auth_recovery_service.dart';
import '../services/arena_backend_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/balance.dart';
import '../core/cerberus_lock_policy.dart';
import '../core/json_utils.dart';
import '../core/log.dart';
import '../core/titles.dart';
import '../models/dungeon.dart';
import '../services/audio_service.dart';
import '../services/lock_service.dart';
import '../services/notification_service.dart';
import '../services/sandbox_manager.dart';
import '../services/step_service.dart';
import '../services/storage_service.dart';
import 'urgent_quest_provider.dart';

part 'game/game_state.dart';
part 'game/game_lifecycle.dart';
part 'game/game_save.dart';
part 'game/game_day.dart';
part 'game/game_dungeons.dart';
part 'game/game_penalty.dart';
part 'game/game_admin.dart';
part 'game/game_xp.dart';

class GameProvider extends _GameBase
    with
        WidgetsBindingObserver,
        _LifecycleLogic,
        _SaveLogic,
        _DayLogic,
        _DungeonLogic,
        _PenaltyLogic,
        _AdminLogic,
        _XpLogic {
  
  // Compatibilité conservée pour les écrans historiques Titres / Arise.
  bool areTitlesActive = true;
  String titlesCooldown = "00:00:00";
  bool isBossKneeling = false;
  bool showAriseEffect = false;
  int shadowExtractionAttempts = 3;

  void attemptArise([dynamic arg]) {
    if (!isBossKneeling) return;
    showAriseEffect = true;
    notifyListeners();
  }

  void cancelExtraction() {
    showAriseEffect = false;
    isBossKneeling = false;
    notifyListeners();
  }

  void closeLevelUpOverlay() {
    _showLevelUpOverlay = false;
    notifyListeners();
  }

  String _persistedLicenseKey = '';
  String _awakeningDate = ''; // GRAVURE DU PREMIER ÉVEIL

  String get licenseKey => _persistedLicenseKey;
  String get awakeningDate => _awakeningDate.isNotEmpty ? _awakeningDate : '--/--/----';

  String get shortLicenseKey {
    if (_persistedLicenseKey.isEmpty) return '';
    final clean = _persistedLicenseKey.trim().toUpperCase();
    if (clean.contains('-')) {
      final parts = clean.split('-');
      if (parts.length >= 2) {
        return "${parts[parts.length - 2]}-${parts[parts.length - 1]}";
      }
    }
    return clean.length > 9 ? clean.substring(clean.length - 9) : clean;
  }

  GameProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initAwakeningDate();
    unawaited(_initializeGameAndLicense());
  }

  Future<void> _initializeGameAndLicense() async {
    await initializeGame();
    await _restoreCachedLicense();
  }

  /// Initialise et grave définitivement la date du premier éveil sur le Hardware
  Future<void> _initAwakeningDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedDate = prefs.getString('shadow_awakening_date');
      
      if (savedDate == null || savedDate.trim().isEmpty) {
        final now = DateTime.now();
        savedDate = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
        await prefs.setString('shadow_awakening_date', savedDate);
      }
      
      _awakeningDate = savedDate;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _restoreCachedLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('shadow_user_license_key')?.trim();
      if (saved == null || saved.isEmpty) return;
      final deviceId = await _getUniqueHardwareId();
      final valid = await ArenaBackendService.validateProLicense(
        key: saved,
        deviceId: deviceId,
      );
      if (!valid) {
        _isPro = false;
        _persistedLicenseKey = null;
        notifyListeners();
        return;
      }
      _persistedLicenseKey = saved;
      _isPro = true;
      notifyListeners();
    } catch (error) {
      // A cached key never grants Pro while the server cannot validate it.
      _isPro = false;
      notifyListeners();
      debugPrint('[PRO] Validation distante indisponible : $error');
    }
  }

  Future<void> saveLicenseLocally(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = key.trim().toUpperCase();
      await prefs.setString('shadow_user_license_key', clean);
      _persistedLicenseKey = clean;
      _isPro = true;
      notifyListeners();
    } catch (_) {}
  }

  void setUrgentQuestProvider(UrgentQuestProvider provider) {
    if (identical(urgentQuestProvider, provider)) return;
    urgentQuestProvider = provider;
    urgentQuestProvider!.onTimeExpired = () {
      triggerPenaltyState("Échec de la Quête Urgente.");
    };
    urgentQuestProvider!.onChanged = () {
      persistGame();
    };
    urgentQuestProvider!.onQuestSuccess = (double xp, int gold) {
      addXp(xp);
      goldCoins += gold;
      persistGame();
    };

    // Restaure la quête chargée avant que le Provider ne soit disponible.
    final pending = _pendingUrgentJson;
    if (pending != null) {
      _pendingUrgentJson = null;
      Future.microtask(() {
        if (!identical(urgentQuestProvider, provider)) return;
        provider.restore(pending);
        provider.checkExpired();
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _dungeonTimer?.cancel();
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}