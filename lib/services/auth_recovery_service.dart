// lib/services/auth_recovery_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRecoveryService {
  static const String _backendUrl = "https://shadowburn-webhook.onrender.com/api/recover-key";

  /// Interroge le serveur, récupère la clé en JSON et retourne la chaîne de caractères (Zéro e-mail)
  static Future<String?> fetchKeyForEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": cleanEmail}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? key = data['key'];
        debugPrint("[RECOVER_OK] Clé récupérée instantanément : $key");
        return key;
      } else {
        debugPrint("[RECOVER_ERROR] Erreur serveur (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("[RECOVER_EXCEPTION] Impossible de joindre le serveur : $e");
      return null;
    }
  }

  static Future<bool> restoreProStatusLocally(String email) async {
    return true;
  }
}
