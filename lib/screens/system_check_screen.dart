import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class SystemCheckScreen extends StatefulWidget {
  const SystemCheckScreen({super.key});

  @override
  State<SystemCheckScreen> createState() => _SystemCheckScreenState();
}

class _SystemCheckScreenState extends State<SystemCheckScreen> {
  bool _isLoading = true;
  bool _hasOverlayPermission = false;
  bool _hasStepPermission = false;

  @override
  void initState() {
    super.initState();
    _auditSystem();
  }

  Future<void> _auditSystem() async {
    // Simulation / Vérification des permissions natives requises pour le mode Chasseur
    await Future.delayed(const Duration(seconds: 1));
    
    // Ici tu pourras brancher les plugins de vérification de permissions réels (ex: permission_handler)
    setState(() {
      _hasOverlayPermission = true; // Remplacer par la vérification native d'overlay
      _hasStepPermission = true;    // Remplacer par la vérification des capteurs de pas
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ANALYSE DU SYSTÈME",
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 28,
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Le Système procède à l'audit des protocoles de sécurité du Hardware.",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 40),
              
              _isLoading
                  ? const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.cyanAccent),
                      ),
                    )
                  : Expanded(
                      child: Column(
                        children: [
                          _buildCheckTile(
                            "Permissions d'Affichage (Overlays)",
                            "Nécessaire pour verrouiller l'écran en cas de pénalité.",
                            _hasOverlayPermission,
                          ),
                          const SizedBox(height: 20),
                          _buildCheckTile(
                            "Capteurs de Mouvement (Podomètre)",
                            "Nécessaire pour comptabiliser l'Exercise Snacking.",
                            _hasStepPermission,
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyan[900],
                                side: const BorderSide(color: Colors.cyanAccent),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: (_hasOverlayPermission && _hasStepPermission)
                                  ? () => Navigator.of(context).pop()
                                  : null,
                              child: const Text(
                                "SYNCHRONISATION TERMINÉE",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckTile(String title, String subtitle, bool isOk) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isOk ? Colors.cyanAccent : Colors.redAccent),
      ),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: isOk ? Colors.cyanAccent : Colors.redAccent,
            size: 30,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}