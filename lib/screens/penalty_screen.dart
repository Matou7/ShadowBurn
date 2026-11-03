// lib/screens/penalty_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';

class PenaltyScreen extends StatelessWidget {
  const PenaltyScreen({super.key});


  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    const Color penaltyRed = Color(0xFFFF2E56);

    final int done = game.penaltySquatsDone;
    final int goal = game.penaltyGoal;
    final double ratio = (goal > 0) ? (done / goal).clamp(0.0, 1.0) : 0.0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Color(0xFF2A000A), Colors.black],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: penaltyRed, width: 2),
                        color: penaltyRed.withOpacity(0.1),
                      ),
                      child: const Icon(Icons.warning_amber_rounded, color: penaltyRed, size: 60),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "ZONE DE PÉNALITÉ",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                        color: penaltyRed,
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
                    const SizedBox(height: 35),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 14,
                        backgroundColor: Colors.red.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(penaltyRed),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "$done / $goal SQUATS",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 35),
                    _HoldSquatsButton(
                      penaltyRed: penaltyRed,
                      onValidated: () {
                        game.addReps("Squats", 5);
                      },
                    ),

                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Bouton avec Cooldown anti-spam (2 secondes)
class _HoldSquatsButton extends StatefulWidget {
  final Color penaltyRed;
  final VoidCallback onValidated;

  const _HoldSquatsButton({required this.penaltyRed, required this.onValidated});

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
          backgroundColor: _isOnCooldown ? Colors.grey.shade900 : widget.penaltyRed,
          foregroundColor: Colors.white,
          side: BorderSide(color: _isOnCooldown ? Colors.grey.shade700 : widget.penaltyRed, width: 2),
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