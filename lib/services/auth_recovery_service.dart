// lib/services/auth_recovery_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthRecoveryService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sends the official Firebase password reset email.
  static Future<bool> sendOfficialRecoveryEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return false;
    try {
      await _auth.sendPasswordResetEmail(email: cleanEmail);
      return true;
    } on FirebaseAuthException catch (error) {
      debugPrint("[AUTH_ERROR] ${error.code} | ${error.message}");
      return false;
    } catch (error) {
      debugPrint("[AUTH_ERROR] $error");
      return false;
    }
  }

  /// Signs into the existing email/password account after the user resets or
  /// confirms their password. A verified email is still required for restore.
  static Future<bool> signInWithPassword(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) return false;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      await credential.user?.reload();
      return _auth.currentUser?.emailVerified == true;
    } on FirebaseAuthException catch (error) {
      debugPrint("[AUTH_ERROR] ${error.code} | ${error.message}");
      return false;
    } catch (error) {
      debugPrint("[AUTH_ERROR] $error");
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