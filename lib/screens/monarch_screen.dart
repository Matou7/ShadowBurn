import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class MonarchScreen extends StatefulWidget {
  const MonarchScreen({Key? key}) : super(key: key);

  @override
  State<MonarchScreen> createState() => _MonarchScreenState();
}

class _MonarchScreenState extends State<MonarchScreen> {
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    // Rafraîchir l'écran chaque seconde
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      
      // Vérifie si on a perdu
      gameProvider.checkAwakeningFailure();
      
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = Provider.of<GameProvider>(context);

    // Empêche le retour arrière
    return PopScope(
      canPop: false, 
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.deepPurple.shade900.withOpacity(0.8), Colors.black],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 50),
                const Text(
                  "ÉPREUVE DE CHANGEMENT DE CLASSE",
                  style: TextStyle(color: Colors.purpleAccent, letterSpacing: 1.5, fontSize: 12),
                ),
                const SizedBox(height: 10),
                const Text(
                  "L'ÉVEIL DU MONARQUE",
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'Cinzel'),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Le Système a détecté que vous avez atteint la limite humaine.\nAccomplissez cette épreuve sacrée.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 30),
                
                // --- TIMER ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withOpacity(0.8), width: 2),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.black54,
                    boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.2), blurRadius: 10)]
                  ),
                  child: Text(
                    game.formattedRemainingTime,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3.0,
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // --- BARRES DE PROGRESSION (Utilise les variables modifiables) ---
                _buildQuestBar("ENDURANCE : COURSE", game.classChangeKm, game.goalNationKm, "KM", Colors.cyanAccent),
                const SizedBox(height: 20),
                _buildQuestBar("FORCE : POMPES", game.classChangePompes.toDouble(), game.goalNationPompes.toDouble(), "REPS", Colors.redAccent),
                const SizedBox(height: 20),
                _buildQuestBar("AGILITÉ : ABDOS", game.classChangeAbdos.toDouble(), game.goalNationAbdos.toDouble(), "REPS", Colors.purpleAccent),
                const SizedBox(height: 20),
                _buildQuestBar("VIGUEUR : SQUATS", game.classChangeSquats.toDouble(), game.goalNationSquats.toDouble(), "REPS", Colors.orangeAccent),
                
                const Spacer(),

                // --- BOUTONS DEBUG ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _debugBtn("POMPES +5", () => game.incrementExercise("Pompes")),
                    _debugBtn("ABDOS +5", () => game.incrementExercise("Abdos")),
                    _debugBtn("SQUATS +5", () => game.incrementExercise("Squats")),
                  ],
                ),
                const SizedBox(height: 20),
                
                // --- BOUTON DE FIN ---
                // Vérifie si TOUS les objectifs sont atteints
                if (game.classChangeKm >= game.goalNationKm && 
                    game.classChangePompes >= game.goalNationPompes && 
                    game.classChangeAbdos >= game.goalNationAbdos && 
                    game.classChangeSquats >= game.goalNationSquats)
                  ElevatedButton(
                    onPressed: () => game.completeClassChange(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 10,
                    ),
                    child: const Text("ACCEPTER LE POUVOIR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  )
                else
                   const Text(
                    "ÉPREUVE EN COURS...",
                    style: TextStyle(color: Colors.white24, letterSpacing: 2),
                  ),
                  
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestBar(String label, double current, double max, String unit, Color color) {
    double progress = (max == 0) ? 1.0 : (current / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            Text("${current.toStringAsFixed(1)} / ${max.toInt()} $unit", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade900,
          color: color,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
  
  Widget _debugBtn(String lbl, VoidCallback act) {
      return TextButton(onPressed: act, child: Text(lbl, style: const TextStyle(color: Colors.white12, fontSize: 10)));
  }
}