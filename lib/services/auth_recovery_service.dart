// lib/services/auth_recovery_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRecoveryService {
  // URL exacte avec "-webhook"
  static const String _backendUrl = "https://shadowburn-webhook.onrender.com/api/recover-key";

  /// Interroge le serveur FastAPI pour retrouver la clé et envoyer l'e-mail Resend
  static Future<bool> sendOfficialRecoveryEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": cleanEmail}),
      );

      if (response.statusCode == 200) {
        debugPrint("[RECOVER_OK] E-mail de récupération expédié par le serveur pour $cleanEmail");
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

  /// Restaure la licence Pro sur l'appareil local (optionnel si géré par l'app)
  static Future<bool> restoreProStatusLocally(String email) async {
    // Garde ta logique locale existante si tu en as besoin
    return true;
  }
}
