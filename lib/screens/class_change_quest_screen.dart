import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class ClassChangeQuestScreen extends StatefulWidget {
  const ClassChangeQuestScreen({Key? key}) : super(key: key);

  @override
  State<ClassChangeQuestScreen> createState() => _ClassChangeQuestScreenState();
}

class _ClassChangeQuestScreenState extends State<ClassChangeQuestScreen> {
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        final game = Provider.of<GameProvider>(context, listen: false);
        game.checkAwakeningFailure();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = Provider.of<GameProvider>(context);

    bool hasStarted = game.isClassChangeStarted;
    bool isTimerRunning = game.formattedRemainingTime != "00:00:00";

    bool isCompleted = game.classChangeKm >= game.goalNationKm &&
        game.classChangePompes >= game.goalNationPompes &&
        game.classChangeAbdos >= game.goalNationAbdos &&
        game.classChangeSquats >= game.goalNationSquats;

    bool isFailed = hasStarted && !isTimerRunning && !isCompleted;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF050505),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                if (isCompleted) Colors.amber.shade900.withValues(alpha: 0.8)
                else if (isFailed) Colors.red.shade900.withValues(alpha: 0.8)
                else Colors.deepPurple.shade900.withValues(alpha: 0.8),
                
                const Color(0xFF000000),
              ],
              stops: const [0.0, 0.6],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 30),

                  // --- EN-TÊTE ---
                  Text(
                    isFailed ? "ÉCHEC DE L'ÉPREUVE" : "ÉPREUVE DE CHANGEMENT DE CLASSE",
                    style: TextStyle(
                      color: isFailed ? Colors.red : Colors.purpleAccent.withValues(alpha: 0.9),
                      letterSpacing: 1.2,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 15)],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isCompleted ? "RANG NATION" : "L'ÉVEIL DU MONARQUE",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontFamily: 'Cinzel', 
                      shadows: [
                        Shadow(color: isCompleted ? Colors.orange : Colors.purple, blurRadius: 20)
                      ]
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- DESCRIPTION ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      isFailed 
                      ? "Vous n'avez pas réussi à transcender vos limites. La pénalité est inévitable (-5M XP)."
                      : (isCompleted 
                          ? "Votre puissance dépasse l'entendement. Acceptez votre nouveau rang."
                          : "Le Système a détecté que vous avez atteint la limite humaine. Pour transcender votre rang, accomplissez cette épreuve sacrée dans le temps imparti."),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- BOUTON DEMARRER OU TIMER ---
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: !hasStarted
                        ? GestureDetector(
                            key: const ValueKey('button'),
                            onTap: () {
                              game.startClassChange();
                              setState(() {}); 
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6A1B9A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFAB47BC), width: 2),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFFAB47BC).withValues(alpha: 0.6), blurRadius: 15, spreadRadius: 1)
                                ],
                              ),
                              child: const Text(
                                "COMMENCER L'ÉPREUVE",
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('timer'),
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A0505),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isFailed ? Colors.red : Colors.redAccent.withValues(alpha: 0.6), width: 1),
                              boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 2)],
                            ),
                            child: Text(
                              game.formattedRemainingTime,
                              style: TextStyle(
                                color: isFailed ? Colors.red : Colors.redAccent,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Courier',
                                letterSpacing: 3.0,
                              ),
                            ),
                          ),
                  ),

                  const SizedBox(height: 30),

                  // --- LISTE DES OBJECTIFS ---
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildObjectiveBar("ENDURANCE : COURSE", game.classChangeKm, game.goalNationKm, "KM", Colors.cyanAccent),
                        _buildObjectiveBar("FORCE : POMPES", game.classChangePompes.toDouble(), game.goalNationPompes.toDouble(), "REPS", const Color(0xFFE53935)),
                        _buildObjectiveBar("AGILITÉ : ABDOS", game.classChangeAbdos.toDouble(), game.goalNationAbdos.toDouble(), "REPS", Colors.purpleAccent),
                        _buildObjectiveBar("VIGUEUR : SQUATS", game.classChangeSquats.toDouble(), game.goalNationSquats.toDouble(), "REPS", Colors.orangeAccent),
                      ],
                    ),
                  ),
                  
                  // --- BOUTONS D'ENTRAINEMENT (NOUVEAU DESIGN) ---
                  // Uniquement visibles si l'épreuve a commencé, n'est pas finie et n'a pas échoué
                  if (hasStarted && isTimerRunning && !isCompleted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                        children: [
                          _buildRectButton("POMPES", () => game.incrementExercise("Pompes")),
                          _buildRectButton("ABDOS", () => game.incrementExercise("Abdos")),
                          _buildRectButton("SQUATS", () => game.incrementExercise("Squats")),
                        ],
                      ),
                    ),

                  // --- BOUTON FINAL ---
                  if (isCompleted || isFailed)
                    GestureDetector(
                      onTap: () {
                         if (isCompleted) {
                           game.completeClassChange(); 
                         } else if (isFailed) {
                           game.applyFailurePenalty(); 
                         }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isCompleted ? Colors.amber.shade800 : Colors.red.shade900,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCompleted ? Colors.yellowAccent : Colors.redAccent,
                            width: 2
                          ),
                          boxShadow: [BoxShadow(color: (isCompleted ? Colors.orange : Colors.red).withValues(alpha: 0.5), blurRadius: 20)],
                        ),
                        child: Center(
                          child: Text(
                            isCompleted ? "ACCEPTER LE POUVOIR" : "ACCEPTER LA PÉNALITÉ",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(height: 60), 

                  const SizedBox(height: 10),
                  const Text(
                    "Une fois le pouvoir extrait, votre ancienne vie prendra fin.",
                    style: TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- NOUVEAU WIDGET BOUTON RECTANGLE ---
  Widget _buildRectButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Design : Fond Noir, Contour Blanc, Rectangulaire
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black, 
          border: Border.all(color: Colors.white, width: 1.0),
          borderRadius: BorderRadius.circular(4), 
          boxShadow: [
             BoxShadow(color: Colors.white.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))
          ]
        ),
        child: Text(
          label, // Texte (ex: POMPES)
          style: const TextStyle(
            color: Colors.white, 
            fontWeight: FontWeight.bold, 
            fontSize: 12,
            letterSpacing: 1.0
          ),
        ),
      ),
    );
  }

  // Widget des barres
  Widget _buildObjectiveBar(String label, double current, double max, String unit, Color color) {
    double progress = (max > 0) ? (current / max).clamp(0.0, 1.0) : 0.0;
    bool isDone = progress >= 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)
              ),
              Text(
                "${current.toInt()} / ${max.toInt()} $unit",
                style: TextStyle(color: isDone ? color : Colors.white60, fontWeight: FontWeight.bold, fontSize: 11)
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3))
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 6,
                width: (MediaQuery.of(context).size.width - 48) * progress,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 0)]
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}