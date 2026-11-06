// lib/screens/dungeon_result_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/game_provider.dart';

class DungeonResultScreen extends StatelessWidget {
  final Map<String, dynamic> result;

  const DungeonResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    bool success = result['status'].toString().contains('VICTOIRE');
    int xp = result['xp'] ?? 0;
    String? lootedKey = result['lootedKey'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              success ? Colors.blueAccent.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
              Colors.black,
            ],
            radius: 1.0,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  success ? "RÉUSSITE" : "ÉCHEC",
                  style: TextStyle(
                    fontSize: 44,
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    color: success ? Colors.cyanAccent : Colors.redAccent,
                    letterSpacing: 4,
                  ),
                ),
                const Text(
                  "RAPPORT DE SYSTÈME",
                  style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2),
                ),
                const SizedBox(height: 36),

                Container(
                  padding: const EdgeInsets.all(26),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("EXPÉRIENCE", style: TextStyle(color: Colors.grey)),
                          Text(
                            "${xp > 0 ? '+' : ''}$xp XP",
                            style: TextStyle(
                              color: xp >= 0 ? Colors.greenAccent : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 30),

                      if (success && lootedKey != null) ...[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text("OBJETS OBTENUS", style: TextStyle(color: Colors.grey, fontSize: 10)),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            const Icon(Icons.vpn_key, color: Colors.amberAccent, size: 30),
                            const SizedBox(width: 15),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("CLÉ DE DONJON", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text("RANG $lootedKey", style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ] else if (success) ...[
                        const Align(
                          alignment: Alignment.center,
                          child: Text("AUCUN OBJET RARE TROUVÉ", style: TextStyle(color: Colors.white24, fontSize: 12, fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A121E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "TÉLÉCHARGER L'APPLICATION SHADOWBURN",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: "https://shadowburn-1d8f8.web.app",
                          version: QrVersions.auto,
                          size: 140.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: success ? Colors.cyanAccent : Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => context.read<GameProvider>().closeResultScreen(),
                    child: const Text("FERMER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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