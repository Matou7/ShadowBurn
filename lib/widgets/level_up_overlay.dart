import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class LevelUpOverlay extends StatefulWidget {
  const LevelUpOverlay({super.key});

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 800)
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller, 
      curve: Curves.elasticOut
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn)
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    // Si le flag n'est pas actif dans le provider, on ne rend rien
    if (!game.showLevelUpOverlay) {
      return const SizedBox.shrink();
    }

    // On lance l'animation dès que le widget est construit et que showLevelUpOverlay est vrai
    if (!_controller.isAnimating && _controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }

    // --- CONFIGURATION DYNAMIQUE SELON LE RANG ---
    final bool isNation = game.lastRankUp == "NATION";
    final Color mainColor = isNation ? const Color(0xFFFFD700) : const Color(0xFF00E5FF);
    final String titleText = isNation ? "AVÈNEMENT" : "LEVEL UP";
    final String subText = isNation 
        ? "CHASSEUR DE RANG NATION" 
        : "VOUS ÊTES PASSÉ AU RANG";
    final String rankText = isNation ? "SS" : game.lastRankUp;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 1. Fond d'assombrissement (Bloque les interactions derrière)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.85),
            ),
          ),
          
          // 2. Contenu de l'Overlay
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: mainColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: mainColor.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- TITRE ---
                      Text(
                        titleText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: mainColor,
                          fontSize: isNation ? 34 : 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.0,
                          shadows: [
                            Shadow(blurRadius: 15, color: mainColor.withValues(alpha: 0.8)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),
                      
                      // --- SOUS-TITRE ---
                      Text(
                        subText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 15),
                      
                      // --- LETTRE DU RANG ---
                      Text(
                        rankText,
                        style: TextStyle(
                          color: mainColor,
                          fontSize: 100,
                          fontWeight: FontWeight.bold,
                          height: 1, // Évite les espaces inutiles
                          shadows: [
                            Shadow(
                              blurRadius: 25, 
                              color: mainColor.withValues(alpha: 0.6),
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 35),
                      
                      // --- BOUTON DE FERMETURE ---
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: mainColor,
                            foregroundColor: Colors.black,
                            elevation: 10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            // Animation de sortie avant de fermer
                            _controller.reverse().then((_) {
                              game.closeLevelUpOverlay();
                            });
                          },
                          child: const Text(
                            "CONTINUER",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}