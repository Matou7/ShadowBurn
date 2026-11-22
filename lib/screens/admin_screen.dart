// lib/screens/admin_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/quota_guard_service.dart';

const Color kSystemBlue = Color(0xFF00E5FF);

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late String _roomId;
  late String _key;
  bool _attemptedAutoLaunch = false;
  bool _isChecking = true;
  bool _isAuthorized = false;
  String _denialReason = "VÉRIFICATION DES DROITS DU MONARQUE...";

  int _relaunchCooldownSeconds = 0;
  Timer? _relaunchCooldownTimer;

  static const int kAdminActionCooldownSeconds = 5;
  static const Duration _kFirestoreTimeout = Duration(seconds: 6);

  static final String _adminSessionId =
      'admin_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = Uri.base;
    String? roomParam = uri.queryParameters['room'];
    String? keyParam = uri.queryParameters['key'];

    if (uri.fragment.contains('?')) {
      final fragmentParams = Uri.splitQueryString(uri.fragment.split('?').last);
      roomParam ??= fragmentParams['room'];
      keyParam ??= fragmentParams['key'];
    }

    _roomId = (roomParam != null && roomParam.trim().isNotEmpty)
        ? roomParam.trim()
        : 'room_1';
    _key = (keyParam ?? '').trim();

    _verifyAdminAccess();
  }

  @override
  void dispose() {
    _relaunchCooldownTimer?.cancel();
    super.dispose();
  }

  void _startRelaunchCooldown() {
    setState(() => _relaunchCooldownSeconds = kAdminActionCooldownSeconds);
    _relaunchCooldownTimer?.cancel();
    _relaunchCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_relaunchCooldownSeconds > 1) {
        setState(() {
          _relaunchCooldownSeconds--;
        });
      } else {
        timer.cancel();
        setState(() {
          _relaunchCooldownSeconds = 0;
        });
      }
    });
  }

  Future<void> _verifyAdminAccess() async {
    if (await QuotaGuardService.isReserveReached()) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason =
              "DONJON ÉPUISÉ — REVENIR DEMAIN.\nLe quota de sécurité journalier (19 500 écritures) est atteint.";
        });
      }
      return;
    }

    if (_key.isEmpty) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason =
              "ACCÈS REFUSÉ : AUCUNE CLÉ MAÎTRE DÉTECTÉE.\nLe mode télécommande requiert une clé Monarque Pro.";
        });
      }
      return;
    }

    try {
      final ref =
          FirebaseFirestore.instance.collection('current_raids').doc(_roomId);
      final doc = await ref.get().timeout(_kFirestoreTimeout);
      if (!doc.exists) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "SALLE INTROUVABLE : La salle [$_roomId] n'existe pas.";
          });
        }
        return;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(doc.data() as Map? ?? {});
      final String expectedKey = (data['admin_key'] ?? '').toString().trim();

      if (expectedKey.isEmpty || expectedKey != _key) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "ACCÈS REFUSÉ : CLÉ MAÎTRE INVALIDE POUR LA SALLE [$_roomId].";
          });
        }
        return;
      }

      final String? activeAdmin = data['active_admin_session']?.toString();
      final int lastAdminActivity =
          (data['admin_last_seen'] as num?)?.toInt() ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;

      if (activeAdmin != null &&
          activeAdmin != _adminSessionId &&
          (now - lastAdminActivity < 600000)) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "ACCÈS BLOQUÉ : UNE SESSION ADMINISTRATEUR EST DÉJÀ ACTIVE SUR UN AUTRE APPAREIL.";
          });
        }
        return;
      }

      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "QUOTA DE SÉCURITÉ ATTEINT.\nAccès administrateur suspendu temporairement.";
          });
        }
        return;
      }

      await ref.update({
        'active_admin_session': _adminSessionId,
        'admin_last_seen': now,
        'last_activity_ms': now,
      }).timeout(_kFirestoreTimeout);

      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = true;
        });

        if (!_attemptedAutoLaunch) {
          _attemptedAutoLaunch = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _launchNativeApp();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason = "Erreur de communication avec le portail : $e";
        });
      }
    }
  }

  Future<void> _launchNativeApp() async {
    if (_relaunchCooldownSeconds > 0) return;
    _startRelaunchCooldown();

    final String customSchemeUrl =
        "shadowburn://admin?room=$_roomId&key=$_key";

    try {
      final schemeUri = Uri.parse(customSchemeUrl);
      await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Erreur ouverture app native: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070D),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF9100)),
              SizedBox(height: 16),
              Text(
                "PASSERELLE TÉLÉCOMMANDE...",
                style: TextStyle(
                    color: Color(0xFFFF9100),
                    fontFamily: 'monospace',
                    letterSpacing: 2),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF04101E),
                border: Border.all(color: const Color(0xFFFF2E56), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_bad, color: Color(0xFFFF2E56), size: 54),
                  const SizedBox(height: 16),
                  const Text(
                    "CONTRÔLE MAÎTRE BLOQUÉ",
                    style: TextStyle(
                        color: Color(0xFFFF2E56),
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _denialReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bool isCooldown = _relaunchCooldownSeconds > 0;

    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF04101E),
                border: Border.all(color: const Color(0xFFFF9100), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_calls,
                      color: Color(0xFFFF9100), size: 44),
                  const SizedBox(height: 14),
                  const Text(
                    "PASSERELLE TÉLÉCOMMANDE",
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "SALLE : $_roomId",
                    style: const TextStyle(
                        color: Color(0xFFFF9100),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Redirection vers l'application ShadowBurn pour activer la télécommande de la salle.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCooldown
                            ? Colors.white24
                            : const Color(0xFFFF9100),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const BeveledRectangleBorder(),
                      ),
                      icon: Icon(
                          isCooldown ? Icons.timer : Icons.phone_android,
                          color: Colors.black,
                          size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isCooldown
                              ? "PATIENTEZ (${_relaunchCooldownSeconds}S)..."
                              : "OUVRIR DANS SHADOWBURN",
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              fontSize: 12),
                        ),
                      ),
                      onPressed: isCooldown ? null : _launchNativeApp,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "Clé : ${_key.isNotEmpty ? _key : "aucune"}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}