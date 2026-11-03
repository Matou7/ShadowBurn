// lib/services/midnight_executor.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/balance.dart';
import 'notification_service.dart';
import 'lock_service.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final bool introDone = prefs.getBool('has_completed_intro') ?? false;
      if (!introDone) {
        return Future.value(true);
      }

      final bool isVolatile = prefs.getBool(StorageService.keySandboxVolatile) ?? false;
      if (isVolatile) {
        return Future.value(true);
      }

      final String? rawSave = prefs.getString('save_v3');
      if (rawSave == null || rawSave.isEmpty) {
        return Future.value(true);
      }

      final dynamic decoded = jsonDecode(rawSave);
      if (decoded is! Map<String, dynamic>) {
        return Future.value(true);
      }

      final String? lastReset = decoded['lastResetDate'] as String?;
      if (lastReset == null || lastReset.isEmpty) {
        return Future.value(true);
      }

      final bool isSandbox = decoded['sandbox'] == true;
      final bool persistPenalty = decoded['godModePersistPenalty'] == true;
      if (isSandbox && !persistPenalty) {
        return Future.value(true);
      }

      final now = DateTime.now();

      // 1. VÉRIFICATION DE LA PÉNALITÉ DE MINUIT
      final String todayStr = now.toIso8601String().substring(0, 10);

      if (lastReset != todayStr) {
        final dynamic calendar = decoded['calendar'];
        bool isWhiteZone = false;
        
        if (calendar is Map) {
          if (calendar[lastReset] is Map) {
            isWhiteZone = calendar[lastReset]['status'] == 'white_zone';
          }
          if (!isWhiteZone && calendar[todayStr] is Map) {
            isWhiteZone = calendar[todayStr]['status'] == 'white_zone';
          }
        }

        final String rank = (decoded['rank'] as String?) ?? 'E';
        final RankConfig cfg = Balance.of(rank);

        final int dailyCycles = (decoded['dailyCyclesCompleted'] as num?)?.toInt() ?? 0;
        final int pompes = (decoded['pompes'] as num?)?.toInt() ?? 0;
        final int abdos = (decoded['abdos'] as num?)?.toInt() ?? 0;
        final int squats = (decoded['squats'] as num?)?.toInt() ?? 0;
        final double km = (decoded['dailyKm'] as num?)?.toDouble() ?? 0.0;

        final bool cycleMet = dailyCycles > 0;
        final bool quotasMet = pompes >= cfg.goalExo &&
            abdos >= cfg.goalExo &&
            squats >= cfg.goalExo &&
            km >= cfg.goalKm;

        // Si on n'est pas en zone blanche et que la quête a échoué
        if (!isWhiteZone && !cycleMet && !quotasMet) {
          final bool canOverlay = await Permission.systemAlertWindow.isGranted;

          // Lecture du quota actuel de pénalité natif pour ajouter (et non empiler à l'infini)
          final penaltyState = await StorageService.readPenaltyState();
          final int newGoal = penaltyState['active'] ? (penaltyState['squatsGoal'] + 100) : 100;
          final int finalGoal = canOverlay ? newGoal : newGoal + 50;

          await StorageService.writePenaltyState(
            active: true,
            squatsDone: penaltyState['squatsDone'],
            squatsGoal: finalGoal,
          );
          
          if (canOverlay) {
            await LockService.lockScreen(force: true);
          }

          await _triggerPenaltyNotification();
        }

        // On force la mise à jour de la date dans le JSON depuis le background
        // pour empêcher l'empilement infini si le joueur ne lance pas l'app le lendemain.
        decoded['lastResetDate'] = todayStr;
        decoded['dailyCyclesCompleted'] = 0;
        decoded['pompes'] = 0;
        decoded['abdos'] = 0;
        decoded['squats'] = 0;
        decoded['dailyKm'] = 0.0;
        decoded['dailySteps'] = 0;
        
        await prefs.setString('save_v3', jsonEncode(decoded));
      }

      // 2. PROTOCOLE ANTI-FLEMME : EXERCISE SNACKING
      await _checkAntiFlemmeSnacking(decoded, prefs, now);

      return Future.value(true);
    } catch (_) {
      return Future.value(false);
    }
  });
}

Future<void> _checkAntiFlemmeSnacking(
  Map<String, dynamic> save,
  SharedPreferences prefs,
  DateTime now,
) async {
  final int dailyCycles = (save['dailyCyclesCompleted'] as num?)?.toInt() ?? 0;
  if (dailyCycles > 0) return;

  final String todayStr = now.toIso8601String().substring(0, 10);

  int currentTarget = -1;
  if (now.hour >= 8 && now.hour < 10) currentTarget = 8;
  else if (now.hour >= 12 && now.hour < 14) currentTarget = 12;
  else if (now.hour >= 16 && now.hour < 18) currentTarget = 16;
  else if (now.hour >= 20 && now.hour < 22) currentTarget = 20;

  if (currentTarget == -1) return;

  final String slotKey = 'antiflemme_slot_${todayStr}_$currentTarget';

  if (prefs.getBool(slotKey) == true) return;

  final Map<int, Map<String, String>> contextualQuotes = {
    8: {
      "title": "[ SNACKING 08:00 : RÉVEIL HARDWARE ]",
      "body": "Les civils dorment encore. Enclenche le premier bloc : 10 pompes tempo 2-2-2."
    },
    12: {
      "title": "[ SNACKING 12:00 : RECHARGE INCINÉRATEUR ]",
      "body": "Avant les munitions, paye ton tribut au Système. 15 squats explosifs maintenant."
    },
    16: {
      "title": "[ SNACKING 16:00 : BRISE-INERTIE ]",
      "body": "Baisse de tension détectée. Gainage vacuum et 10 abdos pour réveiller le Software."
    },
    20: {
      "title": "[ SNACKING 20:00 : DERNIÈRE LIGNE DROITE ]",
      "body": "Minuit approche. La Zone de Pénalité attend les traînards. Boucle ton quota."
    },
  };

  final alert = contextualQuotes[currentTarget] ?? {
    "title": "[ RAPPEL DE DISCIPLINE ]",
    "body": "Validation des blocs exigée. Exécute tes répétitions."
  };

  await NotificationService.init();
  await NotificationService.showAntiFlemmeAlert(
    alert["title"]!,
    alert["body"]!,
  );

  await prefs.setBool(slotKey, true);
}

Future<void> _triggerPenaltyNotification() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidDetails = AndroidNotificationDetails(
    'shadowburn_penalty_channel',
    'Zone de Pénalité',
    channelDescription: 'Notifications critiques de non-accomplissement des quêtes',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    color: Color(0xFFFF0000),
    playSound: true,
    enableVibration: true,
  );
  const notificationDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    999,
    '[ ALERTE DU SYSTÈME ]',
    'Quête quotidienne incomplète. Zone de Pénalité enclenchée. Squats requis mis à jour.',
    notificationDetails,
  );
}

class MidnightExecutor {
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    await Workmanager().registerPeriodicTask(
      "shadowburn_midnight_check",
      "midnightPenaltyCheck",
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}