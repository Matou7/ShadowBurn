// lib/services/auth_recovery_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRecoveryService {
  static const String _backendUrl = "https://shadowburn-webhook.onrender.com/api/recover-key";

  /// Interroge le serveur FastAPI pour réinitialiser used=false, envoyer l'e-mail et valider
  static Future<bool> sendOfficialRecoveryEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": cleanEmail}),
      );

      if (response.statusCode == 200) {
        debugPrint("[RECOVER_OK] Clé réinitialisée (used=false) et e-mail expédié pour $cleanEmail");
        return true;
      } else {
        debugPrint("[RECOVER_ERROR] Erreur serveur (${response.statusCode}): ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("[RECOVER_EXCEPTION] Impossible de joindre le serveur : $e");
      return false;
    }
  }

  static Future<bool> restoreProStatusLocally(String email) async {
    return true;
  }
}
