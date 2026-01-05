import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';

class SystemDialog extends StatelessWidget {
  final String title;
  final String message;
  final Widget? content;
  final List<Widget>? actions;
  final Color color;
  final bool isWarning;

  const SystemDialog({
    super.key,
    this.title = "NOTIFICATION",
    this.message = "",
    this.content,
    this.actions,
    this.color = const Color(0xFF00E5FF),
    this.isWarning = false,
  });

  // --- ANIMATION "SANDWICH" (DÉROULEMENT VERTICAL) ---
  static void show(BuildContext context, {
    String title = "NOTIFICATION",
    String message = "",
    Widget? content,
    List<Widget>? actions,
    Color color = const Color(0xFF00E5FF),
    bool isWarning = false,
    bool autoClose = false, // Pour les quêtes urgentes qui disparaissent seules
  }) {
    AudioService.playSystemNotification();

    showGeneralDialog(
      context: context,
      barrierDismissible: !isWarning, // Si Urgent, on ne peut pas cliquer à côté
      barrierLabel: "Fermer",
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 250), // Très rapide
      pageBuilder: (ctx, anim1, anim2) {
        return SystemDialog(
          title: title,
          message: message,
          content: content,
          actions: actions,
          color: isWarning ? const Color(0xFFFF0000) : color, // Rouge pur si urgent
          isWarning: isWarning,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        // L'animation Sandwich : Scale sur l'axe Y uniquement
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack, // Effet rebond mécanique
          ),
          alignment: Alignment.center, // S'ouvre depuis le milieu
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(15),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // FOND & BORDURE PRINCIPALE
          Container(
            padding: const EdgeInsets.all(2), // Epaisseur bordure externe
            decoration: BoxDecoration(
              color: color.withOpacity(0.6), // Couleur de la bordure brillante
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)
              ],
            ),
            child: Container(
              color: const Color(0xFF050505), // Fond noir intérieur
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- HEADER STYLE ANIME ---
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.2), Colors.transparent],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter
                      ),
                      border: Border(bottom: BorderSide(color: color.withOpacity(0.5))),
                    ),
                    child: Row(
                      children: [
                        // ICÔNE CERCLE
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2),
                          ),
                          child: Icon(
                            isWarning ? Icons.priority_high : Icons.notifications,
                            color: color, size: 20,
                          ),
                        ),
                        const SizedBox(width: 15),
                        // TITRE ENCADRÉ
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 15),
                          decoration: BoxDecoration(
                            border: Border.all(color: color.withOpacity(0.7)),
                            color: Colors.black,
                          ),
                          child: Text(
                            title.toUpperCase(),
                            style: GoogleFonts.orbitron(
                              color: color,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              shadows: [Shadow(color: color, blurRadius: 15)]
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- CONTENU ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 30, 25, 30),
                    child: Column(
                      children: [
                        if (message.isNotEmpty)
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.rajdhani(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (content != null) ...[
                          const SizedBox(height: 20),
                          content!,
                        ],
                      ],
                    ),
                  ),

                  // --- ACTIONS (Barre du bas) ---
                  if (actions != null && actions!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border(top: BorderSide(color: color.withOpacity(0.3))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions!.map((w) => Padding(padding: const EdgeInsets.only(left: 15), child: w)).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // --- DÉCORATION COINS TECH (STYLE ANIME) ---
          // Coin Haut-Gauche
          Positioned(top: -2, left: -2, child: _Corner(color: color)),
          // Coin Haut-Droite
          Positioned(top: -2, right: -2, child: RotatedBox(quarterTurns: 1, child: _Corner(color: color))),
          // Coin Bas-Gauche
          Positioned(bottom: -2, left: -2, child: RotatedBox(quarterTurns: 3, child: _Corner(color: color))),
          // Coin Bas-Droite
          Positioned(bottom: -2, right: -2, child: RotatedBox(quarterTurns: 2, child: _Corner(color: color))),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final Color color;
  const _Corner({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: 4),
          left: BorderSide(color: color, width: 4),
        )
      ),
    );
  }
}