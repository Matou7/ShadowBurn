import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockService {
  static const MethodChannel _channel = MethodChannel('com.shadowburn.lock/channel');

  static const String _persistedLockKey = 'cerberus_lock_active';
  static bool _isLocked = false;
  static bool get isLocked => _isLocked;

  static Future<void> _persistLock(bool locked) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_persistedLockKey, locked);
      await prefs.reload();
    } catch (e) {
      print('Erreur persistance Cerbère : $e');
    }
  }

  /// Active le verrouillage Cerbère uniquement s'il n'est pas déjà engagé
  static Future<void> lockScreen({bool force = false}) async {
    if (_isLocked && !force) return;
    // Persist before calling Android: process death must not erase the lock intent.
    await _persistLock(true);
    _isLocked = true;
    try {
      await _channel.invokeMethod('lockScreen');
    } on PlatformException catch (e) {
      // Keep the local state armed so a later resume can retry the native lock.
      print("Erreur LockService (lock) : ${e.message}");
    } on MissingPluginException catch (e) {
      print("Canal Cerbère indisponible : $e");
    }
  }

  /// Lève le verrouillage uniquement s'il est engagé
  static Future<void> unlockScreen({bool force = false}) async {
    if (!_isLocked && !force) return;
    try {
      await _channel.invokeMethod('unlockScreen');
      _isLocked = false;
      await _persistLock(false);
    } on PlatformException catch (e) {
      // Never clear the persisted lock if Android did not confirm the release.
      _isLocked = true;
      print("Erreur LockService (unlock) : ${e.message}");
    } on MissingPluginException catch (e) {
      _isLocked = true;
      print("Canal Cerbère indisponible : $e");
    }
  }

  /// Ouvre directement l'application Téléphone en mode d'exemption natif
  static Future<void> openEmergencyDialer() async {
    try {
      await _channel.invokeMethod('openEmergencyDialer');
    } on PlatformException catch (e) {
      print("Erreur openEmergencyDialer : ${e.message}");
    }
  }

  /// Ouvre directement l'application SMS en mode d'exemption natif
  static Future<void> openEmergencySms() async {
    try {
      await _channel.invokeMethod('openEmergencySms');
    } on PlatformException catch (e) {
      print("Erreur openEmergencySms : ${e.message}");
    }
  }

  /// Enclenche la fenêtre de tir temporisée et arme le chien de garde pour Appel/SMS
  static Future<void> startEmergencyExemption() async {
    try {
      await _channel.invokeMethod('triggerEmergencyExemption');
    } on PlatformException catch (e) {
      print("Erreur startEmergencyExemption : ${e.message}");
    }
  }

  /// Réinitialise l'exemption d'urgence (quand ShadowBurn repasse devant)
  static Future<void> cancelEmergencyExemption() async {
    try {
      await _channel.invokeMethod('resetEmergencyExemption');
    } on PlatformException catch (e) {
      print("Erreur cancelEmergencyExemption : ${e.message}");
    }
  }

  /// Demande la permission d'affichage par-dessus les autres applications
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      print("Erreur Overlay Permission : ${e.message}");
    }
  }
}