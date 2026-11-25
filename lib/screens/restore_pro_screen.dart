// lib/screens/restore_pro_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_recovery_service.dart';

class RestoreProScreen extends StatefulWidget {
  const RestoreProScreen({super.key});

  @override
  State<RestoreProScreen> createState() => _RestoreProScreenState();
}

class _RestoreProScreenState extends State<RestoreProScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  Future<void> _handleVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _statusMessage = "Veuillez entrer une adresse e-mail valide.";
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Réinitialisation de la clé et envoi en cours...";
      _isSuccess = false;
    });

    bool success = false;
    try {
      success = await AuthRecoveryService.sendOfficialRecoveryEmail(email)
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {
      success = false;
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSuccess = success;
      _statusMessage = success
          ? "Clé réinitialisée et envoyée par e-mail !"
          : "Aucune licence active trouvée pour cet e-mail ou délai dépassé.";
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "[SYSTÈMES] Clé renvoyée ! Entrez-la pour activer le Pass Pro."),
          backgroundColor: Color(0xFF00FF66),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        title: const Text(
          "RESTAURATION DU RANG",
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Center(
              child: Icon(
                Icons.shield_outlined,
                size: 72,
                color: Color(0xFF00E5FF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "RÉCUPÉRATION DU STATUT MONARQUE",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Saisissez l'e-mail de votre achat. Le système remet votre clé à disposition et vous l'envoie par e-mail.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Color(0xFFAAAAAA), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF14141E),
                hintText: "chasseur@domaine.com",
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon:
                    const Icon(Icons.email_outlined, color: Color(0xFF00E5FF)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF00FF66), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Text(
                      "VÉRIFIER LA RESTAURATION",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? const Color(0xFF00FF66).withValues(alpha: 0.1)
                      : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isSuccess
                        ? const Color(0xFF00FF66)
                        : Colors.redAccent,
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isSuccess
                        ? const Color(0xFF00FF66)
                        : Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}