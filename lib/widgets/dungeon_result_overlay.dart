import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class DungeonResultOverlay extends StatelessWidget {
  const DungeonResultOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final result = game.dungeonResult;

    // Si pas de résultat en attente, on cache l'overlay
    if (result == null) return const SizedBox.shrink();

    // Détermine si c'est une victoire
    bool isVictory = result['status'].toString().contains('VICTOIRE');
    int xp = result['xp'] ?? 0;
    
    // Couleur thématique (Bleu pour victoire, Rouge pour défaite)
    Color themeColor = isVictory ? Colors.blueAccent : Colors.red;

    return Material(
      color: Colors.black.withOpacity(0.95),
      child: InkWell(
        onTap: () => game.closeResultScreen(), // Cliquer n'importe où pour fermer
        child: Center(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              border: Border.all(color: themeColor, width: 3),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: themeColor.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result['status'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: themeColor,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 30),
                
                // Affiche l'XP gagné ou perdu
                if (xp != 0) 
                  Text(
                    xp > 0 ? "+$xp XP" : "$xp XP",
                    style: TextStyle(
                      color: xp > 0 ? Colors.purpleAccent : Colors.red,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                const SizedBox(height: 20),
                const Text(
                  "Appuyez pour continuer",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}