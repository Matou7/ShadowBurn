// lib/widgets/penalty_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../services/lock_service.dart';
import '../widgets/system_dialog.dart';

class PenaltyOverlay extends StatelessWidget {
  const PenaltyOverlay({super.key});

  Future<void> _makeEmergencyCall(BuildContext context) async {
    try {
      await LockService.openEmergencyDialer();
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, "Erreur canal d'appel : $e");
    }
  }

  Future<void> _sendEmergencySMS(BuildContext context) async {
    try {
      await LockService.openEmergencySms();
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, "Erreur canal message : $e");
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showAmnestyConfirmDialog(BuildContext context, GameProvider game) {
    LockService.grantEmergencyGrace();
    SystemDialog.show(
      context,
      title: "RECOURS D'URGENCE (AMNISTIE)",
      color: const Color(0xFF00E5FF),
      content: const Text(
        "Ce recours d'urgence purge la Pénalité suite à un dysfonctionnement matériel ou d'affichage.\n\n"
        "• Aucun gain d'XP ou d'Or n'est attribué.\n"
        "• Utilisable strictement une seule fois tous les 30 jours (ou à volonté en God Mode).",
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANNULER"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.25),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: const BorderSide(color: Color(0xFF00E5FF)),
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            final String result = await game.useEmergencyAmnesty();
            final bool granted = result.contains("ACCORDÉE");
            messenger.showSnackBar(
              SnackBar(
                content: Text(result),
                backgroundColor:
                    granted ? const Color(0xFF00FF66) : Colors.redAccent,
                duration: const Duration(seconds: 4),
              ),
            );
          },
          child: const Text("EXÉCUTER L'AMNISTIE",
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    if (!game.isInPenaltyZone) {
      return const IgnorePointer(child: SizedBox.shrink());
    }

    final int goal = game.penaltyGoal > 0 ? game.penaltyGoal : 100;
    final double progressRatio =
        (game.penaltySquatsDone / goal).clamp(0.0, 1.0);

    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent, width: 2),
                    color: Colors.redAccent.withValues(alpha: 0.1),
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 60, color: Colors.redAccent),
                ),
                const SizedBox(height: 20),
                Text(
                  "ZONE DE PÉNALITÉ",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.orbitron(
                    color: Colors.redAccent,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  "Vous n'avez pas accompli votre quête quotidienne.\nLa survie exige de la discipline.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rajdhani(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 40),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    color: Colors.redAccent,
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    minHeight: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "${game.penaltySquatsDone} / $goal SQUATS",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                _HoldSquatsButton(
                  onValidated: () {
                    game.addReps("Squats", 5);
                  },
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _makeEmergencyCall(context),
                        icon: const Icon(Icons.call,
                            color: Colors.orange, size: 16),
                        label: Text(
                          "APPEL",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.orbitron(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _sendEmergencySMS(context),
                        icon: const Icon(Icons.message,
                            color: Colors.orange, size: 16),
                        label: Text(
                          "MESSAGE",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.orbitron(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      backgroundColor:
                          const Color(0xFF00E5FF).withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.shield_moon_outlined,
                        size: 16, color: Color(0xFF00E5FF)),
                    label: Text(
                      "RECOURS D'URGENCE (AMNISTIE 1/30J)",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF00E5FF)),
                    ),
                    onPressed: () => _showAmnestyConfirmDialog(context, game),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldSquatsButton extends StatefulWidget {
  final VoidCallback onValidated;

  const _HoldSquatsButton({required this.onValidated});

  @override
  State<_HoldSquatsButton> createState() => _HoldSquatsButtonState();
}

class _HoldSquatsButtonState extends State<_HoldSquatsButton> {
  int _lastClickTime = 0;
  bool _isOnCooldown = false;
  Timer? _cooldownTimer;

  void _onTap() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastClickTime < 2000) {
      return;
    }
    _lastClickTime = now;

    setState(() {
      _isOnCooldown = true;
    });

    Vibration.vibrate(duration: 40);
    widget.onValidated();

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _isOnCooldown = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _isOnCooldown ? Colors.grey.shade900 : Colors.red.shade900,
          foregroundColor: Colors.white,
          side: BorderSide(
              color: _isOnCooldown ? Colors.grey.shade700 : Colors.redAccent,
              width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: _isOnCooldown ? null : _onTap,
        child: Text(
          _isOnCooldown ? "TEMPO (2-2-2)..." : "FAIRE 5 SQUATS",
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: _isOnCooldown ? Colors.white54 : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}