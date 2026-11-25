// lib/widgets/arise_overlay.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class AriseOverlay extends StatefulWidget {
  const AriseOverlay({super.key});

  @override
  State<AriseOverlay> createState() => _AriseOverlayState();
}

class _AriseOverlayState extends State<AriseOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = Provider.of<GameProvider>(context);

    if (!game.isBossKneeling) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Container(
          color: Colors.black.withValues(alpha: 0.85),
          width: double.infinity,
          height: double.infinity,
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person,
                size: 100,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 20),
              const Text(
                "L'ENNEMI EST VAINCU",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 18,
                  fontFamily: 'Roboto',
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "L'EXTRACTION DE L'OMBRE EST POSSIBLE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 50),
              GestureDetector(
                onTap: () {
                  game.attemptArise("BOSS DU DONJON");
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 15),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border:
                              Border.all(color: Colors.blueAccent, width: 2),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                        child: const Text(
                          "DEBOUT",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                blurRadius: 10.0,
                                color: Colors.blue,
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Essais restants : ${3 - game.shadowExtractionAttempts}",
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),
              TextButton(
                onPressed: () => game.cancelExtraction(),
                child: const Text(
                  "Annuler l'extraction",
                  style: TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
        if (game.showAriseEffect)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.purpleAccent,
                  strokeWidth: 6,
                ),
              ),
            ),
          ),
      ],
    );
  }
}