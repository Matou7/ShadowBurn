// lib/widgets/urgent_quest_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../providers/urgent_quest_provider.dart';

class UrgentQuestOverlay extends StatelessWidget {
  const UrgentQuestOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final quest = context.watch<UrgentQuestProvider>();

    if (!quest.isActive && quest.status != QuestStatus.success) {
      return const SizedBox.shrink();
    }

    String progressText;
    if (quest.type == "Distance") {
      progressText =
          "${quest.progress.toStringAsFixed(2)} / ${quest.targetAmount.toStringAsFixed(2)} km";
    } else {
      progressText =
          "${quest.progress.toInt()} / ${quest.targetAmount.toInt()}";
    }

    final bool isSuccess = quest.status == QuestStatus.success;
    final Color mainColor = isSuccess ? const Color(0xFF00FF66) : Colors.redAccent;
    final IconData mainIcon = isSuccess ? Icons.check_circle_outline : Icons.warning_amber_rounded;
    final String titleText = isSuccess ? "SURVIE VALIDÉE" : "ALERTE DU SYSTÈME";

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0000),
                  border: Border.all(color: mainColor, width: 3),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: mainColor.withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      mainIcon,
                      color: mainColor,
                      size: 70,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      titleText,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                        color: mainColor,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isSuccess 
                          ? "Quête accomplie avec succès !\n+ ${quest.lastXpReward} XP  |  + ${quest.lastGoldReward} OR" 
                          : quest.description,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 25),
                    if (!isSuccess) ...[
                      Text(
                        "${quest.remainingSeconds} s",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          color: mainColor,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: mainColor.withValues(alpha: 0.6),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: (quest.targetAmount > 0)
                              ? (quest.progress / quest.targetAmount).clamp(0.0, 1.0)
                              : 0,
                          backgroundColor: Colors.black,
                          valueColor: AlwaysStoppedAnimation<Color>(mainColor),
                          minHeight: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        progressText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          color: Colors.grey,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30),
                      if (quest.type == "Pompes")
                        _HoldQuestButton(
                          label: "POMPES (+5)",
                          color: Colors.red.shade900,
                          onValidated: () {
                            context.read<GameProvider>().addReps("Pompes", 5);
                            quest.addProgress(5, "Pompes");
                          },
                        ),
                      if (quest.type == "Squats")
                        _HoldQuestButton(
                          label: "SQUATS (+5)",
                          color: Colors.red.shade900,
                          onValidated: () {
                            context.read<GameProvider>().addReps("Squats", 5);
                            quest.addProgress(5, "Squats");
                          },
                        ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.redAccent, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => context.read<GameProvider>().fleeUrgentQuest(),
                          child: Text(
                            "FUIR (PÉNALITÉ)",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.orbitron(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 15),
                      Text(
                        "SYNCHRONISATION DES GAINS EFFECTUÉE",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ]
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

class _HoldQuestButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onValidated;

  const _HoldQuestButton({
    required this.label,
    required this.color,
    required this.onValidated,
  });

  @override
  State<_HoldQuestButton> createState() => _HoldQuestButtonState();
}

class _HoldQuestButtonState extends State<_HoldQuestButton> {
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
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isOnCooldown ? Colors.grey.shade900 : widget.color,
          foregroundColor: Colors.white,
          side: BorderSide(color: _isOnCooldown ? Colors.grey.shade700 : Colors.redAccent, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _isOnCooldown ? null : _onTap,
        child: Text(
          _isOnCooldown ? "TEMPO..." : widget.label,
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: _isOnCooldown ? Colors.white54 : Colors.white,
          ),
        ),
      ),
    );
  }
}