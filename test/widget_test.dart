// ============================================================
// SHADOWBURN V3 - TEST UNITAIRE DE L'ESPRIT (SOFTWARE)
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadowburnv2/providers/game_provider.dart';
import 'package:shadowburnv2/providers/urgent_quest_provider.dart';

// Importe ton fichier principal ou définis ton test avec le widget racine exact
// Assure-toi que le nom de ta classe principale dans main.dart correspond (ex: ShadowBurnApp)
// Si ton application utilise un autre nom de classe racine, remplace-le ci-dessous.

void main() {
  testWidgets('ShadowBurn System Initialization Test', (WidgetTester tester) async {
    // Initialisation du test avec injection des Providers requis par l'application
    // pour garantir que l'environnement de test simule correctement le système du Chasseur.
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GameProvider()),
          ChangeNotifierProvider(create: (_) => UrgentQuestProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('SYSTÈME SHADOWBURN : OPÉRATIONNEL'),
            ),
          ),
        ),
      ),
    );

    // Vérification de la présence du texte système de base
    expect(find.text('SYSTÈME SHADOWBURN : OPÉRATIONNEL'), findsOneWidget);
  });
}