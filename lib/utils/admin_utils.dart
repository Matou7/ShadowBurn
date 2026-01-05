import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../widgets/system_dialog.dart';

// 1. Fenêtre pour entrer le mot de passe (Login)
void showAdminAuthDialog(BuildContext context, GameProvider game) {
  final TextEditingController controller = TextEditingController();

  SystemDialog.show(
    context,
    title: "ACCÈS ADMINISTRATEUR",
    color: const Color(0xFF00E5FF), // Bleu système
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Entrez le code d'autorité pour activer les privilèges système (God Mode).",
          style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: controller,
          style: GoogleFonts.orbitron(color: Colors.white, letterSpacing: 2),
          obscureText: true, // Masque le texte
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "CODE D'ACCÈS",
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text("ANNULER", style: GoogleFonts.rajdhani(color: Colors.grey, fontWeight: FontWeight.bold)),
      ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
          side: const BorderSide(color: Color(0xFF00E5FF)),
        ),
        onPressed: () {
          bool success = game.toggleAdminMode(controller.text);
          Navigator.pop(context);
          
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("GOD MODE ACTIVÉ.", style: GoogleFonts.orbitron()),
                backgroundColor: const Color(0xFF00E5FF),
              )
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("ACCÈS REFUSÉ.", style: GoogleFonts.orbitron()),
                backgroundColor: Colors.red,
              )
            );
          }
        },
        child: Text("INITIALISER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}

// 2. Fenêtre pour changer le mot de passe (Nouveau)
void showChangePasswordDialog(BuildContext context, GameProvider game) {
  final TextEditingController controller = TextEditingController();

  SystemDialog.show(
    context,
    title: "SÉCURITÉ SYSTÈME",
    color: Colors.orangeAccent,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Définir un nouveau code d'accès administrateur.",
          style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: controller,
          style: GoogleFonts.orbitron(color: Colors.white, letterSpacing: 2),
          decoration: const InputDecoration(
            hintText: "NOUVEAU CODE",
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text("ANNULER", style: GoogleFonts.rajdhani(color: Colors.grey, fontWeight: FontWeight.bold)),
      ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orangeAccent.withOpacity(0.2),
          side: const BorderSide(color: Colors.orangeAccent),
        ),
        onPressed: () {
          if (controller.text.isNotEmpty) {
            game.setAdminPassword(controller.text);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Code d'accès mis à jour : ${controller.text}"))
            );
          }
        },
        child: Text("VALIDER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}