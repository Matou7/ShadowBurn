import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class PenaltyScreen extends StatelessWidget {
  const PenaltyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF200505), // Rouge sombre (Sable)
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 80),
              const SizedBox(height: 20),
              const Text(
                "ZONE DE PÉNALITÉ",
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 35,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "Vous n'avez pas terminé votre entraînement quotidien.\nLe Système exige une réparation.",
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              
              // CERCLE DE PROGRESSION PUNITIVE
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: game.penaltySquatsDone / 100.0, // 100 Squats
                      valueColor: const AlwaysStoppedAnimation(Colors.orange),
                      backgroundColor: Colors.redAccent.withOpacity(0.2),
                      strokeWidth: 15,
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        "${100 - game.penaltySquatsDone}",
                        style: const TextStyle(fontSize: 50, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const Text("SQUATS RESTANTS", style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ],
                  )
                ],
              ),
              
              const SizedBox(height: 50),
              
              // BOUTON DE SURVIE
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () {
                    // Simule des squats pour sortir
                    game.incrementExercise("Squats"); 
                  },
                  child: const Text("FAIRE DES SQUATS (+5)", style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
              const Text("SURVIVEZ JUSQU'À LA FIN DU COMPTEUR", style: TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}