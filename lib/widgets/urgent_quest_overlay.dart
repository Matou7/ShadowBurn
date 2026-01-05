import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../providers/urgent_quest_provider.dart';

class UrgentQuestOverlay extends StatelessWidget {
  const UrgentQuestOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final quest = context.watch<UrgentQuestProvider>();
    final game = Provider.of<GameProvider>(context, listen: false);

    if (!quest.isActive) return const SizedBox.shrink();

    String progressText;
    if (quest.type == "Distance") {
        progressText = "${quest.progress.toStringAsFixed(2)} / ${quest.targetAmount.toStringAsFixed(2)} km";
    } else {
        progressText = "${quest.progress.toInt()} / ${quest.targetAmount.toInt()}";
    }

    return Material(
      color: Colors.black.withOpacity(0.95),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0000), 
            border: Border.all(color: Colors.redAccent, width: 3),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 40, spreadRadius: 5)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 70),
              const SizedBox(height: 10),
              const Text("ALERTE", style: TextStyle(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const SizedBox(height: 20),
              Text(quest.description, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              Text("${quest.remainingSeconds} s", style: const TextStyle(color: Colors.red, fontSize: 48, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: (quest.targetAmount > 0) ? (quest.progress / quest.targetAmount).clamp(0.0, 1.0) : 0,
                backgroundColor: Colors.black, color: Colors.red, minHeight: 12,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 10),
              Text(progressText, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              
              if (quest.type == "Pompes")
                _actionBtn("POMPES (+5)", () => game.addReps("Pompes", 5), Colors.red.shade900),
              if (quest.type == "Squats")
                _actionBtn("SQUATS (+5)", () => game.addReps("Squats", 5), Colors.red.shade900),
                
              const SizedBox(height: 15),
              _actionBtn("FUIR (PÉNALITÉ)", () => game.fleeUrgentQuest(), Colors.black),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onTap, Color color) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, side: const BorderSide(color: Colors.redAccent, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}