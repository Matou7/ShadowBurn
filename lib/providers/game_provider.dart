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
  static const String _kPersistentHardwareIdPref = 'shadow_persistent_hw_id_v1';

  String _persistedLicenseKey = '';
  String _awakeningDate = '';
  String? _pairedAdminRoom;
  String? _pairedAdminKey;
  Future<void>? _licenseInitFuture;
  bool _hasPurgedRaidsThisSession = false;

  String get licenseKey => _persistedLicenseKey;
  String get awakeningDate =>
      _awakeningDate.isNotEmpty ? _awakeningDate : '--/--/----';
  String? get pairedAdminRoom => _pairedAdminRoom;
  String? get pairedAdminKey => _pairedAdminKey;
  bool get isAdminPaired =>
      _pairedAdminRoom != null && _pairedAdminRoom!.trim().isNotEmpty;

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
    _licenseInitFuture = _restoreCachedLicense();
    _restorePairedAdminRoom();
    _initAwakeningDate();
    initializeGame();
  }

  Future<bool> ensureProStatusLoaded() async {
    if (_isPro && _persistedLicenseKey.isNotEmpty) return true;
    if (_licenseInitFuture != null) {
      await _licenseInitFuture;
    } else {
      await _restoreCachedLicense();
    }
    return _isPro && _persistedLicenseKey.isNotEmpty;
  }

  Future<void> _restorePairedAdminRoom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final room = prefs.getString('shadow_paired_admin_room');
      final key = prefs.getString('shadow_paired_admin_key');
      if (room != null && room.trim().isNotEmpty) {
        _pairedAdminRoom = room.trim();
        _pairedAdminKey = (key ?? '').trim();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> pairAdminRoom(String roomId, {String adminKey = ''}) async {
    final cleanRoom = roomId.trim();
    if (cleanRoom.isEmpty) return;
    _pairedAdminRoom = cleanRoom;
    _pairedAdminKey = adminKey.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shadow_paired_admin_room', _pairedAdminRoom!);
      await prefs.setString('shadow_paired_admin_key', _pairedAdminKey ?? '');
    } catch (_) {}
  }

  Future<void> unpairAdminRoom() async {
    _pairedAdminRoom = null;
    _pairedAdminKey = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('shadow_paired_admin_room');
      await prefs.remove('shadow_paired_admin_key');
    } catch (_) {}
  }

  Future<void> _initAwakeningDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedDate = prefs.getString('shadow_awakening_date');

      if (savedDate == null || savedDate.trim().isEmpty) {
        final now = DateTime.now();
        savedDate =
            "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
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
        final bool stillValid = await _verifyLicenseWithBackend(
          cleanKey,
          allowOfflineCache: true,
          bindOnServer: false,
        );
        if (stillValid) {
          _persistedLicenseKey = cleanKey;
          _isPro = true;
          notifyListeners();
        } else {
          await revokeProStatusLocally();
        }
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
      debugPrint(
          "[MONARCH SYSTEM] Rétrogradation forcée vers le plan Free : Licence révoquée ou non liée.");
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

  String _generateRandomInstallToken(String prefix) {
    final rng = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final partA =
        List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
    final partB =
        List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
    return "${prefix}_${partA}_$partB";
  }

  @override
  Future<String> getUniqueHardwareIdForCheckout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? existing = prefs.getString(_kPersistentHardwareIdPref);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing.trim();
      }

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String prefix = "DEV";
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        final rawTag =
            (webInfo.vendor ?? 'WEB').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        prefix =
            "WEB_${rawTag.isEmpty ? 'BROWSER' : rawTag.substring(0, min(8, rawTag.length))}";
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final rawModel =
            androidInfo.model.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        prefix =
            "AND_${rawModel.isEmpty ? 'DEVICE' : rawModel.substring(0, min(10, rawModel.length))}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final rawSys =
            iosInfo.systemName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        prefix =
            "IOS_${rawSys.isEmpty ? 'DEVICE' : rawSys.substring(0, min(8, rawSys.length))}";
      }

      final String created = _generateRandomInstallToken(prefix.toUpperCase());
      await prefs.setString(_kPersistentHardwareIdPref, created);
      return created;
    } catch (_) {
      return "UNKNOWN_HARDWARE_ID";
    }
  }

  @override
  Future<bool> requestHardwareAutoRecovery({
    bool silent = false,
    String? email,
    String? proof,
  }) async {
    try {
      final String hwId = await getUniqueHardwareIdForCheckout();
      String? foundKey = await AuthRecoveryService.fetchKeyForHardware(hwId);

      if ((foundKey == null || foundKey.trim().isEmpty) &&
          email != null &&
          email.trim().isNotEmpty &&
          proof != null &&
          proof.trim().isNotEmpty) {
        foundKey = await AuthRecoveryService.recoverKeySecurely(
          email: email,
          proof: proof,
          newHardwareId: hwId,
        );
      }

      if (foundKey != null && foundKey.trim().isNotEmpty) {
        return await activateProKey(foundKey.trim().toUpperCase());
      }
    } catch (e) {
      debugPrint("[AUTH_TRACE] Erreur lors de la récupération : $e");
    }
    return false;
  }

  Future<bool> _verifyLicenseWithBackend(
    String cleanKey, {
    bool allowOfflineCache = false,
    bool bindOnServer = false,
  }) async {
    final String hwId = await getUniqueHardwareIdForCheckout();
    if (cleanKey.trim().isEmpty ||
        hwId.trim().isEmpty ||
        hwId == 'UNKNOWN_HARDWARE_ID') {
      return false;
    }

    try {
      final colRef = FirebaseFirestore.instance.collection('pro_licenses');
      var targetDocRef = colRef.doc(cleanKey);

      final directCheck =
          await targetDocRef.get().timeout(const Duration(seconds: 6));
      if (!directCheck.exists) {
        final querySnap =
            await colRef.where('key', isEqualTo: cleanKey).limit(1).get();
        if (querySnap.docs.isEmpty) {
          return false;
        }
        targetDocRef = querySnap.docs.first.reference;
      }

      if (!bindOnServer) {
        final snap = await targetDocRef.get().timeout(const Duration(seconds: 6));
        if (!snap.exists) {
          return false;
        }
        final rawData = snap.data();
        final Map<String, dynamic> data = rawData != null
            ? Map<String, dynamic>.of(rawData)
            : <String, dynamic>{};

        if (data['revoked'] == true || data['active'] == false) {
          return false;
        }
        if (data['used'] != true) {
          return false;
        }

        final String boundHw = (data['hardware_id'] ?? '').toString().trim();
        final String boundUsedBy = (data['used_by'] ?? '').toString().trim();
        if (boundHw.isNotEmpty && boundHw != hwId) {
          return false;
        }
        if (boundUsedBy.isNotEmpty && boundUsedBy != hwId) {
          return false;
        }
        return true;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(targetDocRef);
        if (!snapshot.exists) {
          throw StateError('Licence introuvable.');
        }

        final rawData = snapshot.data();
        final Map<String, dynamic> data = rawData != null
            ? Map<String, dynamic>.of(rawData)
            : <String, dynamic>{};

        if (data['revoked'] == true || data['active'] == false) {
          throw StateError('Licence révoquée ou inactive.');
        }

        final String boundHw = (data['hardware_id'] ?? '').toString().trim();
        final String boundUsedBy = (data['used_by'] ?? '').toString().trim();

        if (boundHw.isNotEmpty && boundHw != hwId) {
          throw StateError('Licence déjà liée à un autre hardware_id.');
        }
        if (boundUsedBy.isNotEmpty && boundUsedBy != hwId) {
          throw StateError('Licence déjà liée à un autre used_by.');
        }

        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        transaction.update(targetDocRef, {
          'used': true,
          'hardware_id': hwId,
          'used_by': hwId,
          'user_name': _username,
          'used_at': data['used_at'] ?? FieldValue.serverTimestamp(),
          'activated_at_ms': data['activated_at_ms'] ?? nowMs,
          'last_verified_ms': nowMs,
        });
      }).timeout(const Duration(seconds: 8));

      return true;
    } on TimeoutException {
      return allowOfflineCache;
    } on FirebaseException catch (e) {
      debugPrint('[PRO VALIDATION] Firebase ${e.code}: ${e.message}');
      if (allowOfflineCache &&
          (e.code == 'unavailable' ||
              e.code == 'network-request-failed' ||
              e.code == 'deadline-exceeded')) {
        return true;
      }
      return false;
    } on StateError catch (e) {
      debugPrint('[PRO VALIDATION] Refus : ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> activateProKey(String rawKey) async {
    final String cleanKey = rawKey.trim().toUpperCase();
    if (cleanKey.isEmpty || cleanKey.length < 8) return false;

    if (cleanKey == "FREE" || cleanKey == "RESET-PRO") {
      await revokeProStatusLocally();
      return false;
    }

    final bool isVerified = await _verifyLicenseWithBackend(
      cleanKey,
      allowOfflineCache: false,
      bindOnServer: true,
    );
    if (isVerified) {
      await saveLicenseLocally(cleanKey);
      await _forceSaveRealDisk();
      return true;
    }
    return false;
  }

  @override
  Future<void> showOtpRecoveryDialog(BuildContext context) async {
    bool isLoading = false;
    String feedback = "";
    final emailController = TextEditingController();
    final proofController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF121217),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.verified_user, color: Color(0xFF00E5FF)),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      "RESTAURATION SÉCURISÉE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "• Même appareil : cliquez directement sur Restaurer.\n• Nouvel appareil / Réinstallation : entrez votre e-mail Stripe ET votre clé (ou les 4 derniers chiffres de la carte).",
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: "E-mail Stripe (si nouvel appareil)",
                        labelStyle:
                            TextStyle(color: Colors.white38, fontSize: 11),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF00E5FF))),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: proofController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: "Clé Pro OU 4 derniers chiffres carte",
                        labelStyle:
                            TextStyle(color: Colors.white38, fontSize: 11),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF00E5FF))),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                    ),
                    if (feedback.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      Text(
                        feedback,
                        style: TextStyle(
                          color: feedback.contains("SUCCÈS")
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text("ANNULER",
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() {
                            isLoading = true;
                            feedback = "Vérification cryptographique...";
                          });

                          final success = await requestHardwareAutoRecovery(
                            email: emailController.text,
                            proof: proofController.text,
                          );

                          if (!dialogCtx.mounted) return;
                          setDialogState(() {
                            isLoading = false;
                            if (success) {
                              feedback =
                                  "SUCCÈS : Licence vérifiée et transférée !";
                              Future.delayed(const Duration(seconds: 1), () {
                                if (dialogCtx.mounted &&
                                    Navigator.canPop(dialogCtx)) {
                                  Navigator.pop(dialogCtx);
                                }
                              });
                            } else {
                              feedback =
                                  "REFUSÉ : Vérifiez l'e-mail et la clé (ou 4 chiffres carte).";
                            }
                          });
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text("RESTAURER"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> purgeExpiredRaids({bool force = false}) async {
    if (!force && _hasPurgedRaidsThisSession) return;
    _hasPurgedRaidsThisSession = true;

    try {
      final firestore = FirebaseFirestore.instance;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const int staleThresholdMs = 30 * 60 * 1000;
      const int finishedGraceMs = 5 * 60 * 1000;

      final snapshot = await firestore.collection('current_raids').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String status =
            (data['status'] as String? ?? 'waiting').toLowerCase();

        int lastSignalMs = (data['last_activity_ms'] as num?)?.toInt() ?? 0;
        if (lastSignalMs == 0) {
          final dynamic rawLastSeen = data['arena_last_seen'];
          if (rawLastSeen is Timestamp) {
            lastSignalMs = rawLastSeen.millisecondsSinceEpoch;
          } else if (rawLastSeen is int) {
            lastSignalMs = rawLastSeen;
          }
        }

        bool shouldDelete = false;
        if (['finished', 'abandoned', 'closed'].contains(status)) {
          shouldDelete =
              lastSignalMs > 0 && (nowMs - lastSignalMs) > finishedGraceMs;
        } else if (['victory', 'failed'].contains(status)) {
          shouldDelete =
              lastSignalMs > 0 && (nowMs - lastSignalMs) > staleThresholdMs;
        } else if (lastSignalMs > 0 &&
            (nowMs - lastSignalMs) > staleThresholdMs) {
          shouldDelete = true;
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
  void setUrgentQuestProvider(UrgentQuestProvider p) {
    _urgent = p;
    _urgent!.onTimeExpired = () {
      triggerPenaltyState("Échec de la Quête Urgente.");
    };
    _urgent!.onChanged = () {
      persistGame();
    };
    _urgent!.onQuestSuccess = (double xp, int gold) {
      addXp(xp);
      _coins += gold;
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