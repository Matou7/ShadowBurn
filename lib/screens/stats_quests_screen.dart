import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../widgets/system_dialog.dart'; // Nécessaire pour la boîte de dialogue
import 'class_change_quest_screen.dart'; 

class StatsQuestsScreen extends StatefulWidget {
  const StatsQuestsScreen({super.key});

  @override
  State<StatsQuestsScreen> createState() => _StatsQuestsScreenState();
}

class _StatsQuestsScreenState extends State<StatsQuestsScreen> {
  Timer? _timer;
  late int _secondsRemaining;

  @override
  void initState() {
    super.initState();
    _calculateTimeUntilMidnight();
    _startTimer();
  }

  void _calculateTimeUntilMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _secondsRemaining = tomorrow.difference(now).inSeconds;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 0) _secondsRemaining--;
          else _calculateTimeUntilMidnight();
        });
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  // --- FONCTION POUR MODIFIER LES STATS (GOD MODE) ---
  void _showEditDailyStatDialog(BuildContext context, GameProvider game, String label, dynamic currentValue) {
    final controller = TextEditingController(text: currentValue.toString());
    // On nettoie le label pour avoir la clé correcte (ex: "Pompes" -> "pompes")
    final String statKey = label.toLowerCase(); 

    SystemDialog.show(
      context,
      title: "GOD MODE: $label",
      content: TextField(
        controller: controller,
        // Utilisation de numberWithOptions(decimal: true) pour les KM
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: "Nouvelle valeur",
          labelStyle: TextStyle(color: Colors.white54),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.red)),
        ),
      ),
      color: Colors.redAccent,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () {
            // CORRECTION ICI : On utilise num.tryParse pour accepter les nombres à virgule (double)
            num? newVal = num.tryParse(controller.text);
            if (newVal != null) {
              // Appelle la méthode setDailyStat du Provider avec un num (int ou double)
              game.setDailyStat(statKey, newVal);
            }
            Navigator.pop(context);
          }, 
          child: const Text("MODIFIER")
        ),
      ]
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final Color systemBlue = const Color(0xFF00E5FF);

    return Scaffold(
      backgroundColor: Colors.black, 
      body: Container(
        // FOND SCANLINE / DARK UI
        decoration: BoxDecoration(
          color: Colors.black,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, const Color(0xFF001122)], // Très subtile teinte bleue nuit
            stops: const [0.0, 1.0],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 30),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: systemBlue.withOpacity(0.5), width: 2),
            color: Colors.black.withOpacity(0.8),
            // Glow autour du conteneur principal
            boxShadow: [BoxShadow(color: systemBlue.withOpacity(0.15), blurRadius: 30)],
          ),
          child: Column(
            children: [
              _buildQuestHeader(systemBlue),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                    children: [
                      // TIMER GLOWY
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: systemBlue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(4), // Coin tech
                          border: Border.all(color: systemBlue.withOpacity(0.2))
                        ),
                        child: Text(
                          _formatDuration(_secondsRemaining),
                          style: GoogleFonts.orbitron(
                            color: Colors.white, 
                            fontSize: 38, 
                            fontWeight: FontWeight.w500,
                            // GLOW SUR LE TIMER
                            shadows: [
                              Shadow(color: systemBlue, blurRadius: 15),
                              Shadow(color: systemBlue.withOpacity(0.5), blurRadius: 30),
                            ]
                          ),
                        ),
                      ),

                      Text("[Quête Quotidienne : Préparation à la force.]", 
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic)),
                      
                      Column(
                        children: [
                          Text("OBJECTIF", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 5)),
                          const SizedBox(height: 4),
                          Container(width: 60, height: 2, color: Colors.white38),
                        ],
                      ),

                      // LISTE DES OBJECTIFS
                      Column(
                        children: [
                          // On passe 'game' pour pouvoir vérifier le God Mode dans le widget
                          _buildQuestGoal(context, game, "Pompes", game.pompesDone, game.goalPompes, systemBlue),
                          _buildQuestGoal(context, game, "Abdos", game.abdosDone, game.goalAbdos, systemBlue),
                          _buildQuestGoal(context, game, "Squats", game.squatsDone, game.goalSquats, systemBlue),
                          _buildQuestGoal(context, game, "Course", game.kmCycleCurrent, game.goalKm, systemBlue, isKm: true, 
                              onRunToggle: () => game.toggleRunTracking(), isTracking: game.isTrackingRun),
                        ],
                      ),

                      // BOUTONS D'ACTION TECH
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _actionButton("POMPES", () => game.addReps("Pompes", 5), systemBlue),
                          _actionButton("ABDOS", () => game.addReps("Abdos", 5), systemBlue),
                          _actionButton("SQUAT", () => game.addReps("Squats", 5), systemBlue),
                        ],
                      ),
                      
                      if (game.isClassChangeAvailable || game.isClassChangeActive)
                        _holoButton(
                          game.isClassChangeActive ? "ÉPREUVE EN COURS" : "DÉFI DE CLASSE", 
                          Colors.deepPurpleAccent, 
                          () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ClassChangeQuestScreen()))
                        ),

                      Text("ATTENTION : L'échec de la quête entraînera une pénalité.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(color: Colors.redAccent.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
                      
                      const SizedBox(height: 5),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestHeader(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color.withOpacity(0.5)))),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 24),
          const SizedBox(width: 12),
          Text("INFOS QUÊTE", style: GoogleFonts.orbitron(color: color, fontSize: 20, letterSpacing: 5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- WIDGET MODIFIÉ POUR SUPPORTER LE GOD MODE ---
  Widget _buildQuestGoal(BuildContext context, GameProvider game, String title, dynamic current, dynamic goal, Color color, {bool isKm = false, VoidCallback? onRunToggle, bool isTracking = false}) {
    bool isDone = current >= goal;
    
    // Formatage
    String currentStr = isKm ? (current as double).toStringAsFixed(1) : current.toString();
    String goalStr = isKm ? "${(goal as double).toStringAsFixed(1)}km" : goal.toString();

    // On enveloppe tout dans un GestureDetector
    return GestureDetector(
      onLongPress: () {
        // ACTIVATION DU MENU DE TRICHE SI GOD MODE ACTIF
        // J'ai supprimé la restriction sur les KM
        if (game.isGodMode) { 
           _showEditDailyStatDialog(context, game, title, current);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0), 
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(title, style: GoogleFonts.rajdhani(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
                  // Petit indicateur visuel si God Mode actif
                  if (game.isGodMode) 
                    const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.edit, size: 12, color: Colors.redAccent)),
                ],
              ),
            ),
            if (isKm) ...[
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: onRunToggle,
                  icon: Icon(isTracking ? Icons.pause_circle_filled : Icons.play_circle_fill, color: color, size: 22),
                ),
                const SizedBox(width: 8),
            ],
            Text("[$currentStr / $goalStr]", 
              style: GoogleFonts.orbitron(color: isDone ? color : Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Icon(isDone ? Icons.check_box : Icons.check_box_outline_blank, color: isDone ? color : Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.5)), 
          borderRadius: BorderRadius.circular(4), // Coin tech 4px
          color: color.withOpacity(0.1),
        ),
        child: Text(label, style: GoogleFonts.orbitron(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _holoButton(String text, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4)
        ),
        child: Center(child: Text(text, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2))),
      ),
    );
  }
}