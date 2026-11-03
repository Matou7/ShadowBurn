import 'dart:async';
import 'package:flutter/services.dart';

class LockService {
  static const MethodChannel _channel = MethodChannel('com.shadowburn.lock/channel');

  static bool _isLocked = false;
  static bool get isLocked => _isLocked;

  /// Active le verrouillage Cerbère uniquement s'il n'est pas déjà engagé
  static Future<void> lockScreen({bool force = false}) async {
    if (_isLocked && !force) return;
    try {
      _isLocked = true;
      await _channel.invokeMethod('lockScreen');
    } on PlatformException catch (e) {
      _isLocked = false;
      print("Erreur LockService (lock) : ${e.message}");
    }
  }

  /// Lève le verrouillage uniquement s'il est engagé
  static Future<void> unlockScreen({bool force = false}) async {
    if (!_isLocked && !force) return;
    try {
      _isLocked = false;
      await _channel.invokeMethod('unlockScreen');
    } on PlatformException catch (e) {
      print("Erreur LockService (unlock) : ${e.message}");
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