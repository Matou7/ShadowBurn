// lib/services/auth_recovery_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRecoveryService {
  static const String _backendUrl = "https://shadowburn-webhook.onrender.com/api/recover-key";

  /// Interroge le serveur FastAPI pour réinitialiser la licence et la récupérer instantanément en JSON
  static Future<bool> sendOfficialRecoveryEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": cleanEmail}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? recoveredKey = data['key'];
        
        if (recoveredKey != null && recoveredKey.isNotEmpty) {
          debugPrint("[RECOVER_OK] Clé récupérée avec succès pour $cleanEmail : $recoveredKey");
          // Tu peux optionnellement stocker ou appliquer directement la clé ici si besoin
        }
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
