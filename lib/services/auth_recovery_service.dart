// lib/services/auth_recovery_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthRecoveryService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Vérifie l'existence de la licence Pro puis envoie l'e-mail officiel Google
  static Future<bool> sendOfficialRecoveryEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final query = await _db
          .collection('pro_licenses')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        debugPrint("[AUTH_WARN] Aucune licence trouvée pour $cleanEmail");
        return false;
      }

      await _auth.sendPasswordResetEmail(email: cleanEmail);
      debugPrint("[AUTH_OK] E-mail officiel expédié à $cleanEmail");
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint("[AUTH_ERROR] Code: ${e.code} | Message: ${e.message}");
      return false;
    } catch (e) {
      debugPrint("[AUTH_ERROR] Exception: $e");
      return false;
    }
  }

  /// Exige une session Firebase réellement connectée et vérifiée.
  /// Un lien de réinitialisation envoyé n'est pas une preuve d'identité.
  static Future<bool> hasVerifiedSessionForEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return false;

    try {
      User? user = _auth.currentUser;
      if (user == null) return false;

      await user.reload();
      user = _auth.currentUser;

      return user != null &&
          user.emailVerified &&
          (user.email ?? '').trim().toLowerCase() == cleanEmail;
    } catch (e) {
      debugPrint("[AUTH_WARN] Session de récupération non vérifiée : $e");
      return false;
    }
  }
}