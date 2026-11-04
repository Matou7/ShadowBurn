import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/arena_backend_service.dart';

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
    _roomId = roomParam?.trim().isNotEmpty == true ? roomParam!.trim() : 'room_1';
    _key = keyParam ?? '';
    _verifyAdminAccess();
  }

  Future<void> _verifyAdminAccess() async {
    if (_key.trim().isEmpty) {
      if (mounted) setState(() {
        _isChecking = false;
        _isAuthorized = false;
        _denialReason = "ACCÈS REFUSÉ : AUCUNE CLÉ MAÎTRE DÉTECTÉE.";
      });
      return;
    }
    try {
      final valid = await ArenaBackendService.verifyAdminKey(
        roomId: _roomId,
        adminKey: _key.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isAuthorized = valid;
        _denialReason = valid ? '' : "ACCÈS REFUSÉ : CLÉ MONARQUE INVALIDE.";
      });
      if (valid && !_attemptedAutoLaunch) {
        _attemptedAutoLaunch = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _launchNativeApp();
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isAuthorized = false;
        _denialReason = "ÉCHEC DE VALIDATION SERVEUR : $error";
      });
    }
  }

  Future<void> _launchNativeApp() async {
    final intent = Uri.parse(
      "intent://admin?room=$_roomId&key=$_key#Intent;scheme=shadowburn;package=com.example.shadowburnv2;end;",
    );
    final custom = Uri.parse("shadowburn://admin?room=$_roomId&key=$_key");
    try {
      if (await canLaunchUrl(intent)) {
        await launchUrl(intent, mode: LaunchMode.externalNonBrowserApplication);
        return;
      }
    } catch (_) {}
    try {
      await launchUrl(custom, mode: LaunchMode.externalNonBrowserApplication);
    } catch (error) {
      debugPrint("Erreur ouverture app native: $error");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070D),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF9100))),
      );
    }
    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _denialReason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF2E56), fontFamily: 'monospace'),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF04101E),
            border: Border.all(color: const Color(0xFFFF9100), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, color: Color(0xFFFF9100), size: 48),
              const SizedBox(height: 16),
              const Text("CONTRÔLE MAÎTRE DU JEU",
                style: TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text("SALLE : $_roomId",
                style: const TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace')),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _launchNativeApp,
                icon: const Icon(Icons.phone_android),
                label: const Text("OUVRIR DANS L'APPLICATION"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
