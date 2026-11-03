// lib/widgets/dungeon_result_overlay.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/game_provider.dart';

class DungeonResultOverlay extends StatelessWidget {
  const DungeonResultOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final result = game.dungeonResult;

    if (result == null) return const SizedBox.shrink();

    bool isVictory = result['status'].toString().contains('VICTOIRE');
    int xp = result['xp'] ?? 0;

    Color themeColor = isVictory ? Colors.blueAccent : Colors.red;

    return Material(
      color: Colors.black.withValues(alpha: 0.95),
      child: InkWell(
        onTap: () => game.closeResultScreen(),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border.all(color: themeColor, width: 3),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: themeColor.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 5)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result['status'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: themeColor,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (xp != 0)
                    Text(
                      xp > 0 ? "+$xp XP" : "$xp XP",
                      style: TextStyle(
                        color: xp > 0 ? Colors.purpleAccent : Colors.red,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  // ESPACEMENT NET AVANT LE QR CODE APPLI
                  const SizedBox(height: 36),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "APPLICATION SHADOWBURN",
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: QrImageView(
                            data: "https://shadowburn-1d8f8.web.app",
                            version: QrVersions.auto,
                            size: 130.0,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    "Appuyez pour continuer",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}