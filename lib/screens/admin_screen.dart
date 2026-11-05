// lib/screens/admin_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _key = keyParam ?? '';

    _verifyAdminAccess();
  }

  Future<void> _verifyAdminAccess() async {
    if (_key.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason = "ACCÈS REFUSÉ : AUCUNE CLÉ MAÎTRE DÉTECTÉE.\nLe mode télécommande requiert une clé Monarque Pro.";
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('current_raids').doc(_roomId).get();
      if (!doc.exists) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason = "SALLE INTROUVABLE : La salle [$_roomId] n'existe pas.";
          });
        }
        return;
      }

      final data = doc.data() as Map<String, dynamic>? ?? {};
      final String expectedKey = (data['admin_key'] ?? '').toString().trim();

      if (expectedKey.isEmpty || expectedKey != _key.trim()) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason = "ACCÈS REFUSÉ : CETTE SALLE N'A PAS D'ADMINISTRATEUR ACTIF OU LA CLÉ EST INVALIDE.\nRéservé aux détenteurs du statut Monarque Pro.";
          });
        }
        return;
      }

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
    final String androidIntentUrl =
        "intent://admin?room=$_roomId&key=$_key#Intent;scheme=shadowburn;package=com.shadowburn.app;end;";
    final String customSchemeUrl = "shadowburn://admin?room=$_roomId&key=$_key";

    try {
      final intentUri = Uri.parse(androidIntentUrl);
      if (await canLaunchUrl(intentUri)) {
        await launchUrl(intentUri, mode: LaunchMode.externalNonBrowserApplication);
        return;
      }
    } catch (_) {}

    try {
      final schemeUri = Uri.parse(customSchemeUrl);
      await launchUrl(schemeUri, mode: LaunchMode.externalNonBrowserApplication);
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
                "CONTRÔLE DU STATUT DU MAÎTRE...",
                style: TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace', letterSpacing: 2),
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
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _denialReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Passez au statut Monarque Pro pour héberger des raids et commander les sessions.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF9100).withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.security, color: Color(0xFFFF9100), size: 44),
                  const SizedBox(height: 14),
                  const Text(
                    "CONTRÔLE MAÎTRE DU JEU",
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "SALLE : $_roomId",
                    style: const TextStyle(
                      color: Color(0xFFFF9100),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Liaison chiffrée. La télécommande est exclusivement disponible sur l'application ShadowBurn installée.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9100),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const BeveledRectangleBorder(),
                      ),
                      icon: const Icon(Icons.phone_android, color: Colors.black, size: 20),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "OUVRIR DANS L'APPLICATION",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      onPressed: _launchNativeApp,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "Token de sécurité : ${_key.isNotEmpty ? _key : "aucun"}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontFamily: 'monospace',
                      fontSize: 9,
                    ),
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