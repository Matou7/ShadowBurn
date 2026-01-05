import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class TitlesScreen extends StatelessWidget {
  const TitlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("INVENTAIRE DES TITRES", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // BANDEAU DE SANCTION (Si titres désactivés suite à une mort)
          if (!game.areTitlesActive)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withOpacity(0.2),
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  const Icon(Icons.warning, color: Colors.redAccent),
                  const SizedBox(height: 5),
                  const Text("MALÉDICTION DU SYSTÈME", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  Text(
                    "Titres désactivés pendant encore ${game.titlesCooldown}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),

          // LISTE DES TITRES
          Expanded(
            child: ListView.builder(
              itemCount: game.unlockedTitles.length,
              itemBuilder: (context, index) {
                final title = game.unlockedTitles[index];
                final isEquipped = game.equippedTitle == title;
                
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    border: Border.all(
                      color: isEquipped ? Colors.cyanAccent : Colors.grey[800]!,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    title: Text(
                      title, 
                      style: TextStyle(
                        color: isEquipped ? Colors.cyanAccent : Colors.white,
                        fontWeight: FontWeight.bold
                      )
                    ),
                    subtitle: Text(
                      _getTitleEffect(title), 
                      style: TextStyle(
                        color: game.areTitlesActive ? Colors.grey : Colors.grey[800], // Grisé si inactif
                        fontSize: 12
                      )
                    ),
                    trailing: isEquipped 
                      ? const Icon(Icons.check_circle, color: Colors.cyanAccent)
                      : TextButton(
                          onPressed: game.areTitlesActive 
                            ? () => context.read<GameProvider>().equipTitle(title)
                            : null, // Bouton désactivé si sanction
                          child: const Text("ÉQUIPER"),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Descriptions Cosmétiques
  String _getTitleEffect(String title) {
    switch (title) {
      case "Adversaire d'Acier": return "Bonus: +5 Force (Cosmétique)";
      case "Marcheur de l'Ombre": return "Bonus: Récupération PV améliorée (Cosmétique)";
      case "Petit de Rang E": return "Titre de départ.";
      case "Nouveau Chasseur": return "Aucun bonus spécial";
      case "Autorité Nationale": return "Titre Légendaire. Impose le respect.";
      case "Monarque des Ombres": return "Titre Divin. Vous avez transcendé la mort.";
      default: return "Effet inconnu";
    }
  }
}