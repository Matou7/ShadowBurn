// lib/services/boot_service.dart

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'storage_service.dart';

class BootService {
  static const MethodChannel _channel = MethodChannel('com.shadowburn.app/boot');

  static Future<void> initBootListener(Function onPenaltyRestored) async {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == "onBootWithPenalty") {
          onPenaltyRestored();
        }
      });
      await checkPendingDungeonsOnBoot();
    } catch (e) {
      print("Erreur BootService : $e");
    }
  }

  static Future<void> registerBootReceiver() async {
    try {
      await _channel.invokeMethod('registerBootReceiver');
    } catch (e) {
      print("Boot receiver non pris en charge sur cette plateforme : $e");
    }
  }

  static Future<void> checkPendingDungeonsOnBoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final bool isVolatile = prefs.getBool(StorageService.keySandboxVolatile) ?? false;
      if (isVolatile) return;

      final String? rawSave = prefs.getString('save_v3');
      if (rawSave == null || rawSave.isEmpty) return;

      final dynamic decoded = jsonDecode(rawSave);
      if (decoded is! Map<String, dynamic>) return;

      final DateTime now = DateTime.now();

      final dynamic dj = decoded['dungeon'];
      if (dj is Map) {
        final expiresAtStr = dj['expiresAt'] as String?;
        if (expiresAtStr != null) {
          final DateTime? expiry = DateTime.tryParse(expiresAtStr);
          if (expiry != null && now.isAfter(expiry)) {
            await NotificationService.showNotification(
              "ASPIRATION IMMÉDIATE",
              "Le portail dimensionnel s'est refermé sur vous. Combat requis !",
              type: 'dungeon',
            );
            return;
          }
        }
      }

      final threats = decoded['threats'];
      if (threats is List && threats.isNotEmpty) {
        for (final t in threats) {
          if (t is Map) {
            final expiresAtStr = t['expiresAt'] as String?;
            if (expiresAtStr != null) {
              final DateTime? expiry = DateTime.tryParse(expiresAtStr);
              if (expiry != null && now.isAfter(expiry)) {
                await NotificationService.showNotification(
                  "ASPIRATION DU PORTAIL",
                  "Le temps de grâce est écoulé. Le Système vous jette dans le donjon !",
                  type: 'dungeon',
                );
                return;
              }
            }
          }
        }
      }
    } catch (_) {}
  }
}