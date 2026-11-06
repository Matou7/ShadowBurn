// lib/screens/intro_awakening_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

class IntroAwakeningScreen extends StatefulWidget {
  final Function(String hunterName) onIntroComplete;

  const IntroAwakeningScreen({super.key, required this.onIntroComplete});

  @override
  State<IntroAwakeningScreen> createState() => _IntroAwakeningScreenState();
}

enum IntroStep {
  injunction,
  tempoExplanation,
  trialTimer,
  congratulations,
  lawDaily,
  lawMidnight,
  lawPortals,
  lawUrgent,
  peaksWarning,
  nameEntry,
  finalAwakening,
}

class _IntroAwakeningScreenState extends State<IntroAwakeningScreen> {
  IntroStep _currentStep = IntroStep.injunction;

  String _displayedText = "";
  String _fullTargetText = "";
  Timer? _typewriterTimer;
  bool _isTyping = false;

  int _secondsRemaining = 65;
  Timer? _trialCountdownTimer;
  bool _trialFinished = false;

  final TextEditingController _nameController = TextEditingController();
  final Color _systemCyan = const Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _loadStepContent();
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _trialCountdownTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _vibrateLight() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 30);
    }
  }

  void _vibrateHeavy() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 200, 100, 300]);
    }
  }

  void _startTypewriter(String text) {
    _typewriterTimer?.cancel();
    setState(() {
      _fullTargetText = text;
      _displayedText = "";
      _isTyping = true;
    });

    int charIndex = 0;
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (charIndex < _fullTargetText.length) {
        setState(() {
          _displayedText += _fullTargetText[charIndex];
        });
        charIndex++;
      } else {
        timer.cancel();
        setState(() {
          _isTyping = false;
        });
      }
    });
  }

  void _loadStepContent() {
    switch (_currentStep) {
      case IntroStep.injunction:
        _startTypewriter(
          "Entité non identifiée détectée.\n\n"
          "Le Système n'accepte aucun spectateur. Prouvez que votre enveloppe physique est fonctionnelle avant d'espérer franchir le seuil.",
        );
        break;

      case IntroStep.tempoExplanation:
        _startTypewriter(
          "PROTOCOLE PHYSIQUE IMPOSÉ :\n10 Squats en tension mécanique continue.\n\n"
          "— 2 secondes de descente contrôlée.\n"
          "— 2 secondes de blocage isométrique en bas.\n"
          "— 2 secondes de remontée explosive.\n\n"
          "Zéro élan toléré. Verrouillez la sangle abdominale.",
        );
        break;

      case IntroStep.trialTimer:
        _displayedText = "";
        _fullTargetText = "";
        _isTyping = false;
        _startTrialCountdown();
        break;

      case IntroStep.congratulations:
        _vibrateHeavy();
        _startTypewriter(
          "Analyse du Hardware validée.\n\n"
          "Félicitations : vous avez été sélectionné pour devenir un Joueur.\n\n"
          "Prenez immédiatement connaissance des lois inflexibles qui régissent votre existence.",
        );
        break;

      case IntroStep.lawDaily:
        _startTypewriter(
          "LOI I : L'INCINÉRATEUR QUOTIDIEN\n\n"
          "Chaque jour, un tribut physique est exigé : Pompes, Abdos, Squats et Course.\n\n"
          "Votre quota doit être accompli avant 00h00 précises. Au-delà, c'est l'échec critique.\n\n"
          "Le surpassement au-delà du quota accorde des multiplicateurs d'XP et des récompenses rares.",
        );
        break;

      case IntroStep.lawMidnight:
        _startTypewriter(
          "LOI II : LE CHÂTIMENT DE MINUIT\n\n"
          "Si votre quête reste incomplète aux douze coups de minuit, le Système prend le contrôle de l'appareil.\n\n"
          "L'accès est immédiatement verrouillé. Aucune fuite possible : seuls 100 squats complets permettent de lever le confinement.",
        );
        break;

      case IntroStep.lawPortals:
        _startTypewriter(
          "LOI III : LES FAILLES DIMENSIONNELLES\n\n"
          "Des donjons apparaîtront de manière imprévisible au cours de la journée.\n\n"
          "Franchir un portail est irréversible : l'arène vous retient captif tant que le quota d'exercice n'est pas purgé.\n\n"
          "Si vous ignorez une faille et que le délai expire, le portail vous aspirera de force, même au redémarrage de l'appareil.",
        );
        break;

      case IntroStep.lawUrgent:
        _startTypewriter(
          "LOI IV : LES QUÊTES URGENTES\n\n"
          "Des anomalies temporaires surgiront aléatoirement pour tester votre réactivité.\n\n"
          "Aucune sanction n'est appliquée en cas d'ignorance. En revanche, ceux qui relèvent le défi récoltent un apport d'XP et d'or.",
        );
        break;

      case IntroStep.peaksWarning:
        _startTypewriter(
          "AVERTISSEMENT DU SYSTÈME :\n\n"
          "Ne vous complaisez pas dans le Rang E. Vous n'êtes qu'au seuil de l'abîme.\n\n"
          "Deux sommets attendent les véritables Chasseurs :\n\n"
          "• ÉPREUVE NATIONALE (48h) : 200 Pompes, 200 Abdos, 200 Squats, 20 km.\n\n"
          "• TRÔNE DU MONARQUE (72h) : 400 Pompes, 400 Abdos, 400 Squats, 40 km.\n\n"
          "Préparez votre corps dès aujourd'hui.",
        );
        break;

      case IntroStep.nameEntry:
        _startTypewriter(
          "REGISTRE DES CHASSEURS :\n\n"
          "Déclinez votre identité matricielle. Entrez votre nom de code pour graver votre existence dans le Système :",
        );
        break;

      case IntroStep.finalAwakening:
        _vibrateHeavy();
        final name = _nameController.text.trim().isEmpty ? "Chasseur" : _nameController.text.trim();
        _startTypewriter(
          "SYNCHRONISATION TERMINÉE.\n\n"
          "Licence délivrée : Rang E.\n\n"
          "Bienvenue dans le Système, $name.\n"
          "Votre vie antérieure s'arrête ici.\n\n"
          "Relevez-vous.",
        );
        break;
    }
  }

  void _startTrialCountdown() {
    _secondsRemaining = 65;
    _trialFinished = false;
    _trialCountdownTimer?.cancel();

    _trialCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        _vibrateHeavy();
        setState(() {
          _trialFinished = true;
        });
      }
    });
  }

  String _formatTimer(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return "$m:$sec";
  }

  void _nextStep() {
    _vibrateLight();
    setState(() {
      switch (_currentStep) {
        case IntroStep.injunction:
          _currentStep = IntroStep.tempoExplanation;
          break;
        case IntroStep.tempoExplanation:
          _currentStep = IntroStep.trialTimer;
          break;
        case IntroStep.trialTimer:
          _currentStep = IntroStep.congratulations;
          break;
        case IntroStep.congratulations:
          _currentStep = IntroStep.lawDaily;
          break;
        case IntroStep.lawDaily:
          _currentStep = IntroStep.lawMidnight;
          break;
        case IntroStep.lawMidnight:
          _currentStep = IntroStep.lawPortals;
          break;
        case IntroStep.lawPortals:
          _currentStep = IntroStep.lawUrgent;
          break;
        case IntroStep.lawUrgent:
          _currentStep = IntroStep.peaksWarning;
          break;
        case IntroStep.peaksWarning:
          _currentStep = IntroStep.nameEntry;
          break;
        case IntroStep.nameEntry:
          if (_nameController.text.trim().isNotEmpty) {
            _currentStep = IntroStep.finalAwakening;
          }
          break;
        case IntroStep.finalAwakening:
          _finishIntro();
          return;
      }
      _loadStepContent();
    });
  }

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_intro', true);
    final hunterName = _nameController.text.trim().isEmpty ? "Chasseur" : _nameController.text.trim();
    widget.onIntroComplete(hunterName);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    "[ SYSTÈME : PROTOCOLE D'ÉVEIL ]",
                    style: GoogleFonts.orbitron(
                      color: _systemCyan,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _systemCyan.withOpacity(0.8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: _systemCyan.withOpacity(0.15),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_currentStep == IntroStep.trialTimer) ...[
                            Center(
                              child: Text(
                                "ÉPREUVE DU HARDWARE EN COURS",
                                style: GoogleFonts.orbitron(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.redAccent, width: 2),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black45,
                                ),
                                child: Text(
                                  _formatTimer(_secondsRemaining),
                                  style: GoogleFonts.orbitron(
                                    color: Colors.redAccent,
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4.0,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            const Text(
                              "OBJECTIF : 10 Squats Tempo 2-2-2.\n\n"
                              "Descendez en 2 secondes, tenez 2 secondes au point bas, remontez en 2 secondes.\n\n"
                              "Maintenez la cadence jusqu'à l'extinction du chronomètre.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                            ),
                          ] else ...[
                            Text(
                              _displayedText,
                              style: GoogleFonts.rajdhani(
                                color: Colors.white,
                                fontSize: 17,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_currentStep == IntroStep.nameEntry && !_isTyping) ...[
                              const SizedBox(height: 25),
                              TextField(
                                controller: _nameController,
                                style: GoogleFonts.orbitron(
                                  color: _systemCyan,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.black54,
                                  hintText: "VOTRE NOM DE CODE...",
                                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: _systemCyan.withOpacity(0.5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: _systemCyan, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildActionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (_isTyping) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white12,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: () {
          _typewriterTimer?.cancel();
          setState(() {
            _displayedText = _fullTargetText;
            _isTyping = false;
          });
        },
        child: const Text("PASSER L'ANIMATION", style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    if (_currentStep == IntroStep.trialTimer) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _trialFinished ? _systemCyan : Colors.white12,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: _trialFinished ? _nextStep : null,
        child: Text(
          _trialFinished ? "QUOTA EXÉCUTÉ" : "ÉPREUVE EN COURS...",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: _trialFinished ? Colors.black : Colors.white24,
          ),
        ),
      );
    }

    String label = "SUIVANT";
    if (_currentStep == IntroStep.injunction) label = "AFFICHER LE PROTOCOLE";
    if (_currentStep == IntroStep.tempoExplanation) label = "INITIALISER LE TEST (01:05)";
    if (_currentStep == IntroStep.lawUrgent) label = "ACCEPTER LE PACTE";
    if (_currentStep == IntroStep.peaksWarning) label = "JE SUIS PRÊT";
    if (_currentStep == IntroStep.nameEntry) label = "GRAVER DANS LA MATRICE";
    if (_currentStep == IntroStep.finalAwakening) label = "ENTRER DANS LE SYSTÈME";

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _systemCyan,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 6,
      ),
      onPressed: _nextStep,
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.5),
      ),
    );
  }
}