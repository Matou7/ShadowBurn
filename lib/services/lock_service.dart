// lib/services/lock_service.dart
import 'dart:async';
import 'package:flutter/services.dart';

class LockService {
  static const MethodChannel _primaryChannel = MethodChannel('com.shadowburn.app/lock');
  static const MethodChannel _legacyChannel = MethodChannel('com.shadowburn.lock/channel');

  static bool _isLocked = false;
  static bool get isLocked => _isLocked;

  static Future<void> lockScreen({bool force = false}) async {
    if (_isLocked && !force) return;
    try {
      _isLocked = true;
      await _primaryChannel.invokeMethod('lockScreen');
    } catch (_) {
      try {
        await _legacyChannel.invokeMethod('lockScreen');
      } on PlatformException catch (e) {
        _isLocked = false;
        print("Erreur LockService (lock) : ${e.message}");
      }
    }
  }

  static Future<void> unlockScreen({bool force = false}) async {
    if (!_isLocked && !force) return;
    try {
      _isLocked = false;
      await _primaryChannel.invokeMethod('unlockScreen');
    } catch (_) {
      try {
        await _legacyChannel.invokeMethod('unlockScreen');
      } on PlatformException catch (e) {
        print("Erreur LockService (unlock) : ${e.message}");
      }
    }
  }

  static Future<void> openEmergencyDialer() async {
    try {
      await _primaryChannel.invokeMethod('openEmergencyDialer');
    } catch (_) {
      try {
        await _legacyChannel.invokeMethod('openEmergencyDialer');
      } on PlatformException catch (e) {
        print("Erreur openEmergencyDialer : ${e.message}");
      }
    }
  }

  static Future<void> openEmergencySms() async {
    try {
      await _primaryChannel.invokeMethod('openEmergencySms');
    } catch (_) {
      try {
        await _legacyChannel.invokeMethod('openEmergencySms');
      } on PlatformException catch (e) {
        print("Erreur openEmergencySms : ${e.message}");
      }
    }
  }

  static Future<void> startEmergencyExemption() async {
    try {
      await _primaryChannel.invokeMethod('resetEmergencyExemption');
    } catch (_) {
      try {
        await _legacyChannel.invokeMethod('resetEmergencyExemption');
      } on PlatformException catch (e) {
        print("Erreur startEmergencyExemption : ${e.message}");
      }
    }
  }

  static Future<void> cancelEmergencyExemption() async {
    try {
      await _primaryChannel.invokeMethod('resetEmergencyExemption');
    } catch (_) {}
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _primaryChannel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }
}