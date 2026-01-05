import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class PenaltyOverlay extends StatelessWidget {
  const PenaltyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    // Si pas de pénalité, on n'affiche rien (invisible)
    if (!game.isInPenaltyZone) return const SizedBox.shrink();

    return Material(
      color: Colors.black, // Fond noir total pour la punition
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                "ZONE DE PÉNALITÉ",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Vous n'avez pas accompli votre quête quotidienne.\nLa survie exige de la discipline.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 40),
              
              // Barre de progression de la punition
              LinearProgressIndicator(
                value: game.penaltySquatsDone / 100,
                color: Colors.redAccent,
                backgroundColor: Colors.red.withOpacity(0.2),
                minHeight: 15,
              ),
              const SizedBox(height: 10),
              Text(
                "${game.penaltySquatsDone} / 100 SQUATS",
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              
              const SizedBox(height: 50),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  // Utilisation de la méthode publique du provider
                  onPressed: () => game.addReps("Squats", 5),
                  child: const Text("FAIRE 5 SQUATS", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}