// lib/utils/admin_utils.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../widgets/system_dialog.dart';

// 1. Fenêtre pour entrer le mot de passe (Login)
void showAdminAuthDialog(BuildContext context, GameProvider game) {
  // Strictement interdit d'ouvrir l'auth admin en release
  if (!kDebugMode) return;

  final TextEditingController controller = TextEditingController();

  SystemDialog.show(
    context,
    title: "ACCÈS ADMINISTRATEUR",
    color: const Color(0xFF00E5FF),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Entrez le code d'autorité. Le God Mode est un BAC À SABLE : ta progression actuelle est sauvegardée, "
          "puis plus rien n'est enregistré jusqu'à ce que tu choisisses de garder ou d'annuler.",
          style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: controller,
          style: GoogleFonts.orbitron(color: Colors.white, letterSpacing: 2),
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "CODE D'ACCÈS",
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
          ),
          onSubmitted: (_) {
            _executeLogin(context, game, controller.text);
          },
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: () {
          _executeLogin(context, game, controller.text);
        },
        child: Text("INITIALISER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}

void _executeLogin(BuildContext context, GameProvider game, String enteredPassword) {
  if (!kDebugMode) return;
  final messenger = ScaffoldMessenger.of(context);
  final bool success = game.toggleAdminMode(enteredPassword);
  Navigator.pop(context);

  if (success) {
    messenger.showSnackBar(SnackBar(
      content: Text("GOD MODE ACTIVÉ : bac à sable, rien n'est enregistré.", style: GoogleFonts.orbitron(fontSize: 11)),
      backgroundColor: const Color(0xFF00E5FF),
    ));
  } else {
    messenger.showSnackBar(SnackBar(
      content: Text("ACCÈS REFUSÉ.", style: GoogleFonts.orbitron()),
      backgroundColor: Colors.red,
    ));
  }
}

// 2. Fenêtre de sortie du God Mode : garder ou annuler les modifications
void showExitGodModeDialog(BuildContext context, GameProvider game) {
  if (!kDebugMode) return;
  SystemDialog.show(
    context,
    title: "FIN DU MODE ADMIN",
    color: Colors.redAccent,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Tes modifications faites en God Mode ne sont PAS encore enregistrées.\n\n"
          "SAUVEGARDER : tu gardes tout ce que tu as modifié.\n"
          "ABANDONNER : retour exact à l'état d'avant le God Mode.\n"
          "RESTER : tu continues en bac à sable.",
          style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[900],
            side: const BorderSide(color: Colors.white30),
            minimumSize: const Size(double.infinity, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text("RESTER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[900]!,
            minimumSize: const Size(double.infinity, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            game.exitGodMode(keepChanges: false);
            messenger.showSnackBar(const SnackBar(content: Text("Modifications abandonnées : état d'avant restauré.")));
          },
          child: Text("ABANDONNER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
            side: const BorderSide(color: Color(0xFF00E5FF)),
            minimumSize: const Size(double.infinity, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            game.exitGodMode(keepChanges: true);
            messenger.showSnackBar(const SnackBar(content: Text("Modifications sauvegardées.")));
          },
          child: Text("SAUVEGARDER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    ),
    actions: const [],
  );
}

// 3. Fenêtre pour changer le mot de passe
void showChangePasswordDialog(BuildContext context, GameProvider game) {
  if (!kDebugMode) return;
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
          obscureText: true,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: () {
          if (controller.text.isNotEmpty) {
            final messenger = ScaffoldMessenger.of(context);
            game.setAdminPassword(controller.text);
            Navigator.pop(context);
            messenger.showSnackBar(const SnackBar(content: Text("Code d'accès mis à jour.")));
          }
        },
        child: Text("VALIDER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}

// 4. Fenêtre pour modifier une stat en God Mode
void showGodModeStatDialog(BuildContext context, GameProvider game, String statName, int currentVal) {
  if (!kDebugMode || !game.isGodMode) return;
  final TextEditingController controller = TextEditingController(text: currentVal.toString());

  SystemDialog.show(
    context,
    title: "MODIFIER $statName",
    color: const Color(0xFF00E5FF),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: GoogleFonts.orbitron(color: Colors.white, letterSpacing: 2),
          decoration: const InputDecoration(
            labelText: "Nouvelle valeur",
            labelStyle: TextStyle(color: Colors.white54),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: () {
          final val = int.tryParse(controller.text);
          if (val != null) {
            game.setDailyStat(statName, val);
          }
          Navigator.pop(context);
        },
        child: Text("VALIDER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}

// 5. Fenêtre pour modifier la course en God Mode
void showGodModeKmDialog(BuildContext context, GameProvider game, double currentKm) {
  if (!kDebugMode || !game.isGodMode) return;
  final TextEditingController controller = TextEditingController(text: currentKm.toStringAsFixed(1));

  SystemDialog.show(
    context,
    title: "MODIFIER COURSE",
    color: const Color(0xFF00E5FF),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.orbitron(color: Colors.white, letterSpacing: 2),
          decoration: const InputDecoration(
            labelText: "Distance (KM)",
            labelStyle: TextStyle(color: Colors.white54),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: () {
          final val = double.tryParse(controller.text.replaceAll(',', '.'));
          if (val != null) {
            game.setDailyKm(val);
          }
          Navigator.pop(context);
        },
        child: Text("VALIDER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}
