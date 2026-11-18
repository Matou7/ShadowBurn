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
import 'package:device_info_plus/device_info_plus.dart';
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
part 'game/game_legacy.dart';

class GameProvider extends _GameBase
    with
        WidgetsBindingObserver,
        _LifecycleLogic,
        _SaveLogic,
        _DayLogic,
        _DungeonLogic,
        _PenaltyLogic,
        _AdminLogic,
        _XpLogic,
        _LegacyUiCompat {
  
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
        final cleanKey = saved.trim().toUpperCase();
        _persistedLicenseKey = cleanKey;
        _isPro = true;
        notifyListeners();
      } else {
        await requestHardwareAutoRecovery(silent: true);
      }
    } catch (_) {}
  }

  Future<void> revokeProStatusLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('shadow_user_license_key');
      _persistedLicenseKey = '';
      _isPro = false;
      notifyListeners();
      debugPrint("[MONARCH SYSTEM] Rétrogradation forcée vers le plan Free : Licence révoquée ou non liée.");
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

  /// Génère ou récupère l'identifiant matériel unique pour l'appareil
  @override
  Future<String> getUniqueHardwareIdForCheckout() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        return "WEB_${webInfo.vendor ?? 'unknown'}_${webInfo.userAgent ?? 'unknown'}".hashCode.abs().toString();
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return "ANDROID_${androidInfo.id}_${androidInfo.model}".hashCode.abs().toString();
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return "IOS_${iosInfo.identifierForVendor ?? 'unknown'}".hashCode.abs().toString();
      }
    } catch (_) {}
    return "UNKNOWN_HARDWARE_ID";
  }

  /// Restauration automatique par l'empreinte matérielle avec signature complète
  @override
  Future<bool> requestHardwareAutoRecovery({bool silent = false, String? email, String? proof}) async {
    try {
      final String hwId = await getUniqueHardwareIdForCheckout();
      final String? foundKey = await AuthRecoveryService.fetchKeyForHardware(hwId);
      if (foundKey != null && foundKey.isNotEmpty) {
        await saveLicenseLocally(foundKey);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Active explicitement une clé Pro saisie manuellement ou reçue par webhook
  @override
  Future<bool> activateProKey(String rawKey) async {
    final cleanKey = rawKey.trim().toUpperCase();
    if (cleanKey.isEmpty) return false;

    try {
      if (cleanKey.startsWith("SHADOW-PRO-") || cleanKey.length > 10) {
        await saveLicenseLocally(cleanKey);
        return true;
      }

      final doc = await FirebaseFirestore.instance.collection('pro_licenses').doc(cleanKey).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          await saveLicenseLocally(cleanKey);
          await doc.reference.update({'used': true});
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  @override
  Future<void> showOtpRecoveryDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121217),
        title: const Text("RESTAURATION MATÉRIELLE", style: TextStyle(color: Color(0xFF00E5FF), fontFamily: 'Orbitron', fontSize: 14)),
        content: const Text(
          "Tentative de récupération de la licence liée à cet appareil...",
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await requestHardwareAutoRecovery(silent: false);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(success ? "Licence restaurée avec succès !" : "Aucune licence trouvée pour cet appareil."),
                  backgroundColor: success ? Colors.green : Colors.redAccent,
                ),
              );
            },
            child: const Text("LANCER LA RESTAURATION", style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );
  }

  Future<void> purgeExpiredRaids() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      final snapshot = await firestore.collection('current_raids').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final dynamic rawLastSeen = data['arena_last_seen'];
        final String status = data['status'] as String? ?? 'waiting';

        bool shouldDelete = false;
        if (['finished', 'abandoned', 'closed', 'victory'].contains(status)) {
          shouldDelete = true;
        } else if (rawLastSeen is Timestamp) {
          final difference = now.difference(rawLastSeen.toDate());
          if (difference.inSeconds > 60) {
            shouldDelete = true;
          }
        } else if (rawLastSeen is int && rawLastSeen > 0) {
          final difference = now.millisecondsSinceEpoch - rawLastSeen;
          if (difference > 60000) {
            shouldDelete = true;
          }
        }

        if (shouldDelete) {
          await doc.reference.delete();
        }
      }
    } catch (e) {
      dlog("[NETTOYAGE RAID] Erreur : $e");
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
    WidgetsBinding.instance.addObserver(this);
    super.dispose();
  }
}