// lib/providers/game_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../core/balance.dart';
import '../core/json_utils.dart';
import '../core/log.dart';
import '../core/titles.dart';
import '../models/dungeon.dart';
import '../services/audio_service.dart';
import '../services/auth_recovery_service.dart';
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
  
  String _persistedLicenseKey = '';
  String _awakeningDate = '';

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
    _restoreCachedLicense();
    _initAwakeningDate();
    initializeGame();
  }

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
      final saved = prefs.getString('shadow_user_license_key');
      if (saved != null && saved.trim().isNotEmpty) {
        _persistedLicenseKey = saved.trim();
        _isPro = true;
        notifyListeners();
      }
    } catch (_) {}
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

  // Autonettoyage robuste basé sur le TTL (Time-To-Live / arena_last_seen > 60s)
  Future<void> purgeExpiredRaids() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      for (String collectionPath in ['current_raids', 'current_raid']) {
        final snapshot = await firestore.collection(collectionPath).get();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final Timestamp? lastSeen = data['arena_last_seen'] as Timestamp?;
          final String status = data['status'] as String? ?? 'waiting';

          bool shouldDelete = false;
          if (['finished', 'abandoned', 'closed', 'victory'].contains(status)) {
            shouldDelete = true;
          } else if (lastSeen != null) {
            final difference = now.difference(lastSeen.toDate());
            if (difference.inSeconds > 60) {
              shouldDelete = true;
            }
          }

          if (shouldDelete) {
            await doc.reference.delete();
          }
        }
      }
    } catch (e) {
      dlog("[NETTOYAGE RAID] Erreur lors de la purge des salles orphelines : $e");
    }
  }

  @override
  void setUrgentQuestProvider(UrgentQuestProvider provider) {
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
