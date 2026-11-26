// lib/services/lock_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LockService {
  static const MethodChannel _primaryChannel =
      MethodChannel('com.shadowburn.app/lock');
  static const MethodChannel _legacyChannel =
      MethodChannel('com.shadowburn.lock/channel');

  static bool _isLocked = false;
  static bool get isLocked => _isLocked;

  static Future<void> _invokeWithFallback(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      await _primaryChannel.invokeMethod(method, arguments);
    } on PlatformException catch (e) {
      debugPrint("LockService [$method] primary error:${e.message}");
      try {
        await _legacyChannel.invokeMethod(method, arguments);
      } on PlatformException catch (legacyError) {
        debugPrint(
            "LockService [$method] legacy error:${legacyError.message}");
        rethrow;
      }
    } catch (_) {
      await _legacyChannel.invokeMethod(method, arguments);
    }
  }

  static Future<void> lockScreen({bool force = false}) async {
    if (_isLocked && !force) return;
    _isLocked = true;
    try {
      await _invokeWithFallback('lockScreen');
    } catch (_) {
      _isLocked = false;
    }
  }

  static Future<void> unlockScreen({bool force = false}) async {
    if (!_isLocked && !force) return;
    _isLocked = false;
    try {
      await _invokeWithFallback('unlockScreen');
    } catch (_) {}
  }

  static Future<void> grantEmergencyGrace() async {
    try {
      await _invokeWithFallback('grantEmergencyGrace');
    } catch (_) {}
  }

  static Future<void> openEmergencyDialer() async {
    try {
      await _invokeWithFallback('openEmergencyDialer');
    } catch (e) {
      debugPrint("Erreur openEmergencyDialer : $e");
    }
  }

  static Future<void> openEmergencySms() async {
    try {
      await _invokeWithFallback('openEmergencySms');
    } catch (e) {
      debugPrint("Erreur openEmergencySms : $e");
    }
  }

  static Future<void> startEmergencyExemption() async {
    try {
      await _invokeWithFallback('resetEmergencyExemption');
    } catch (e) {
      debugPrint("Erreur startEmergencyExemption : $e");
    }
  }

  static Future<void> cancelEmergencyExemption() async {
    try {
      await _invokeWithFallback('resetEmergencyExemption');
    } catch (_) {}
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _invokeWithFallback('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<void> openUsageSettings() async {
    try {
      await _invokeWithFallback('openUsageSettings');
    } catch (_) {}
  }

  static Future<void> openBatteryNoRestrictions() async {
    try {
      await _invokeWithFallback('openBatteryNoRestrictions');
    } catch (_) {}
  }
}