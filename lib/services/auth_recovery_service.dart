// lib/services/auth_recovery_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRecoveryService {
  static const String _backendUrl = "https://shadowburn-webhook.onrender.com/api/verify-hardware";

  /// Interroge le serveur FastAPI en envoyant l'ID matériel pour récupérer instantanément la clé
  static Future<String?> fetchKeyForHardware(String hardwareId) async {
    final cleanHw = hardwareId.trim();
    if (cleanHw.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"hardware_id": cleanHw}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? key = data['key'];
        debugPrint("[HARDWARE_RECOVER_OK] Clé récupérée pour l'appareil : $key");
        return key;
      } else {
        debugPrint("[HARDWARE_RECOVER_ERROR] Erreur serveur (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("[HARDWARE_RECOVER_EXCEPTION] Impossible de joindre le serveur : $e");
      return null;
    }
  }

  /// Pont de compatibilité pour éviter toute erreur résiduelle
  static Future<String?> fetchKeyForEmail(String email) async {
    return null;
  }

  static Future<bool> sendOfficialRecoveryEmail(String email) async {
    return true;
  }

  static Future<bool> restoreProStatusLocally(String email) async {
    return true;
  }
}
