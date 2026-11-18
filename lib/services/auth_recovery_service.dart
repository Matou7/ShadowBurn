// lib/services/auth_recovery_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRecoveryService {
  static const String _verifyHwUrl = "https://shadowburn-webhook.onrender.com/api/verify-hardware";
  static const String _verifySecureUrl = "https://shadowburn-webhook.onrender.com/api/verify-secure";

  /// 1. Vérification directe par empreinte matérielle (même appareil)
  static Future<String?> fetchKeyForHardware(String hardwareId) async {
    final cleanHw = hardwareId.trim();
    if (cleanHw.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(_verifyHwUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"hardware_id": cleanHw}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['key'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint("[HARDWARE_RECOVER_EXCEPTION] $e");
      return null;
    }
  }

  /// 2. Transfert sécurisé par double preuve
  static Future<String?> recoverKeySecurely({
    required String email,
    required String proof,
    required String newHardwareId,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanProof = proof.trim().toUpperCase();
    if (cleanEmail.isEmpty || cleanProof.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(_verifySecureUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": cleanEmail,
          "proof": cleanProof,
          "hardware_id": newHardwareId.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['key'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint("[SECURE_RECOVER_EXCEPTION] $e");
      return null;
    }
  }

  static Future<String?> fetchKeyForEmail(String email) async => null;
  static Future<bool> sendOfficialRecoveryEmail(String email) async => true;
  static Future<bool> restoreProStatusLocally(String email) async => true;
}