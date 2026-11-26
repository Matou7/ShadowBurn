// lib/services/cerberus_background_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:workmanager/workmanager.dart';
import 'lock_service.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void cerberusCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final penaltyState = await StorageService.readPenaltyState();
      if (penaltyState['active'] == true) {
        await LockService.lockScreen(force: true);
      } else {
        await LockService.unlockScreen(force: true);
      }
    } catch (_) {}
    return Future.value(true);
  });
}

class CerberusBackgroundService {
  static const String taskName = 'cerberus_periodic_check';
  static bool _isInitialized = false;

  static int previousLevel = 1;
  static int currentLevel = 1;
  static int previousMaxHealth = 100;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    await Workmanager().initialize(cerberusCallbackDispatcher);
    _isInitialized = true;
  }

  static Future<void> startPeriodicCheck() async {
    if (!_isInitialized) {
      await initialize();
    }
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> stopPeriodicCheck() async {
    try {
      await Workmanager().cancelByUniqueName(taskName);
    } catch (_) {}
    previousLevel = 1;
    currentLevel = 1;
    previousMaxHealth = 100;
  }

  static Future<void> syncHunterState(String hunterId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('hunters')
          .doc(hunterId)
          .get();

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      currentLevel = (data['level'] as num?)?.toInt() ?? previousLevel;
      final int currentMaxHealth =
          (data['maxHealth'] as num?)?.toInt() ?? previousMaxHealth;

      if (currentLevel > previousLevel ||
          currentMaxHealth != previousMaxHealth) {
        previousLevel = currentLevel;
        previousMaxHealth = currentMaxHealth;
        await FirebaseFirestore.instance
            .collection('hunters')
            .doc(hunterId)
            .update({
          'lastCerberusSync': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }
}