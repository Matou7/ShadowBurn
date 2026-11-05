// lib/screens/inventory_dungeon_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../models/dungeon.dart';
import '../widgets/system_dialog.dart';
import '../services/lock_service.dart';

class CountdownWidget extends StatefulWidget {
  final DateTime targetTime;
  final TextStyle style;
  const CountdownWidget({Key? key, required this.targetTime, required this.style}) : super(key: key);
  @override
  _CountdownWidgetState createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calculateTime());
  }

  void _calculateTime() {
    final now = DateTime.now();
    final diff = widget.targetTime.difference(now);
    if (mounted) setState(() => _timeLeft = diff.isNegative ? Duration.zero : diff);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String timeString = "${twoDigits(_timeLeft.inMinutes.remainder(60))}:${twoDigits(_timeLeft.inSeconds.remainder(60))}";
    if (_timeLeft.inHours > 0) timeString = "${twoDigits(_timeLeft.inHours)}:$timeString";
    return Text(timeString, style: widget.style);
  }
}

class InventoryDungeonScreen extends StatelessWidget {
  const InventoryDungeonScreen({Key? key}) : super(key: key);

  Color _getRankColor(String r) {
    switch (r) {
      case 'E':
        return Colors.grey;
      case 'D':
        return const Color(0xFF4CAF50);
      case 'C':
        return const Color(0xFF2196F3);
      case 'B':
        return const Color(0xFF9C27B0);
      case 'A':
        return const Color(0xFFF44336);
      case 'S':
        return const Color(0xFFFFD700);
      case 'NATION':
        return const Color(0xFF00E5FF);
      default:
        return Colors.blueAccent;
    }
  }

  Future<void> _makeEmergencyCall(BuildContext context) async {
    try {
      await LockService.openEmergencyDialer();
    } catch (e) {
      _showError(context, "Erreur canal d'appel : $e");
    }
  }

  Future<void> _sendEmergencySMS(BuildContext context) async {
    try {
      await LockService.openEmergencySms();
    } catch (e) {
      _showError(context, "Erreur canal message : $e");
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showAmnestyConfirmDialog(BuildContext context, GameProvider game) {
    SystemDialog.show(
      context,
      title: "RECOURS D'URGENCE (AMNISTIE)",
      color: const Color(0xFF00E5FF),
      content: const Text(
        "Ce recours d'urgence referme le Portail sans pénalité en cas d'anomalie matérielle.\n\n"
        "• Aucun gain d'XP, d'Or ou de Clé n'est accordé.\n"
        "• Utilisable strictement une seule fois tous les 30 jours.",
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANNULER"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF).withOpacity(0.25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: const BorderSide(color: Color(0xFF00E5FF)),
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            final String result = await game.useEmergencyAmnesty();
            final bool granted = result.contains("ACCORDÉE");
            messenger.showSnackBar(
              SnackBar(
                content: Text(result),
                backgroundColor: granted ? const Color(0xFF00FF66) : Colors.redAccent,
                duration: const Duration(seconds: 4),
              ),
            );
          },
          child: const Text("EXÉCUTER L'AMNISTIE", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  void _showProRequiredDialog(BuildContext context, GameProvider game, String rank) {
    final controller = TextEditingController();
    SystemDialog.show(
      context,
      title: "ACCÈS MONARQUE REQUIS",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Le portail de rang $rank est réservé aux Chasseurs d'élite ayant éveillé leur statut Pro.",
            style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Entrez votre clé Pro (ex: SHADOW-PRO-XXXX)",
              hintStyle: TextStyle(color: Colors.white30),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
            ),
          ),
        ],
      ),
      color: const Color(0xFF00E5FF),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: const BorderSide(color: Color(0xFF00E5FF)),
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final keyInput = controller.text;
            Navigator.pop(context);

            final bool success = await game.activateProKey(keyInput);
            messenger.showSnackBar(
              SnackBar(
                content: Text(success ? "Statut Pro activé avec succès !" : "Clé invalide."),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          },
          child: const Text("ACTIVER", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, child) {
        final Color systemBlue = const Color(0xFF00E5FF);

        if (game.activeDungeon != null) {
          return _buildActiveDungeonView(context, game, _getRankColor(game.activeDungeon!.rank));
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black, systemBlue.withOpacity(0.03), Colors.black],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 40.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        "DONJONS & CLÉS",
                        style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          shadows: [Shadow(color: systemBlue.withOpacity(0.5), blurRadius: 10)],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (game.activeThreats.isNotEmpty) ...[
                      Text(
                        "⚠️ ANOMALIES DÉTECTÉES",
                        style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: game.activeThreats.length,
                          itemBuilder: (context, index) => _buildThreatCard(context, game, game.activeThreats[index]),
                        ),
                      ),
                      const SizedBox(height: 25),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildKeyCard(context, game, "E", _getRankColor("E"))),
                                const SizedBox(width: 15),
                                Expanded(child: _buildKeyCard(context, game, "D", _getRankColor("D"))),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Expanded(child: _buildKeyCard(context, game, "C", _getRankColor("C"))),
                                const SizedBox(width: 15),
                                Expanded(child: _buildKeyCard(context, game, "B", _getRankColor("B"))),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Expanded(child: _buildKeyCard(context, game, "A", _getRankColor("A"))),
                                const SizedBox(width: 15),
                                Expanded(child: _buildKeyCard(context, game, "S", _getRankColor("S"))),
                              ],
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              child: _buildKeyCard(context, game, "NATION", _getRankColor("NATION")),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKeyCard(BuildContext context, GameProvider game, String rank, Color keyColor) {
    int count = game.inventoryKeys[rank] ?? 0;
    bool hasKey = count > 0;
    final Color systemBlue = const Color(0xFF00E5FF);

    bool isRestricted = (rank == 'C' || rank == 'B' || rank == 'A' || rank == 'S' || rank == 'NATION') && !game.isPro;

    return GestureDetector(
      onLongPress: () {
        if (game.isGodMode) {
          final controller = TextEditingController();
          SystemDialog.show(
            context,
            title: "CHEAT: DÉFINIR CLÉS $rank",
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: "Quantité exacte (ex: 0)", hintStyle: TextStyle(color: Colors.white30)),
            ),
            color: Colors.redAccent,
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: () {
                  int? qty = int.tryParse(controller.text);
                  if (qty != null) {
                    game.setDungeonKey(rank, qty);
                  }
                  Navigator.pop(context);
                },
                child: const Text("VALIDER", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Accès refusé. Activez le mode Admin."),
            duration: Duration(seconds: 1),
          ));
        }
      },
      onTap: () {
        if (isRestricted) {
          _showProRequiredDialog(context, game, rank);
          return;
        }

        if (hasKey) {
          SystemDialog.show(
            context,
            title: "PORTAIL",
            message: "Voulez-vous utiliser une clé de rang $rank pour générer une instance ?",
            color: systemBlue,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("ANNULER", style: GoogleFonts.rajdhani(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: systemBlue.withOpacity(0.2),
                  side: BorderSide(color: systemBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  game.enterDungeon(rank);
                },
                child: Text("CONFIRMER", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      },
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          border: Border.all(color: keyColor.withOpacity(hasKey ? 0.6 : 0.35), width: 2),
          borderRadius: BorderRadius.circular(4),
          boxShadow: hasKey ? [BoxShadow(color: keyColor.withOpacity(0.2), blurRadius: 10)] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // CORRECTION DU CADENAS (stack propre et espacé)
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.vpn_key, color: keyColor.withOpacity(hasKey ? 1.0 : 0.35), size: 30),
                if (isRestricted)
                  Positioned(
                    right: 4,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orangeAccent, width: 1),
                      ),
                      child: const Icon(Icons.lock, color: Colors.orangeAccent, size: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text("RANG $rank", style: GoogleFonts.orbitron(color: keyColor.withOpacity(hasKey ? 1.0 : 0.45), fontWeight: FontWeight.bold, fontSize: 16)),
            Text(hasKey ? "UNITÉ : $count" : (isRestricted ? "PRO REQUIS" : "AUCUNE"), style: GoogleFonts.rajdhani(color: hasKey ? Colors.white70 : Colors.white30, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildThreatCard(BuildContext context, GameProvider game, Dungeon dungeon) {
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        border: Border.all(color: Colors.redAccent.withOpacity(0.8), width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("PORTAIL ROUGE", style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          CountdownWidget(targetTime: dungeon.expiresAt, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              SystemDialog.show(
                context,
                title: "INCURSION FORCÉE",
                message: "Entrer dans l'anomalie de rang ${dungeon.rank} ?",
                isWarning: true,
                color: Colors.redAccent,
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text("FUIR", style: GoogleFonts.rajdhani(color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      game.enterDungeon(dungeon.rank, isThreat: true, threatInstance: dungeon);
                    },
                    child: Text("ENTRER", style: GoogleFonts.orbitron(color: Colors.white)),
                  ),
                ],
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              decoration: BoxDecoration(border: Border.all(color: Colors.redAccent), color: Colors.redAccent.withOpacity(0.2)),
              child: Text("COMBATTRE", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDungeonView(BuildContext context, GameProvider game, Color themeColor) {
    final d = game.activeDungeon!;
    final Color dangerColor = const Color(0xFFF44336);

    final double maxHp = d.maxBossHp;
    final double currentHp = d.currentBossHp;
    final double hpPercent = (currentHp / maxHp).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 20),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: themeColor.withOpacity(0.3)))),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("DONJON ACTIF : RANG ${d.rank}", style: GoogleFonts.orbitron(color: themeColor, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(color: themeColor, blurRadius: 10)])),
                        CountdownWidget(targetTime: d.expiresAt, style: GoogleFonts.orbitron(color: dangerColor, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Transform.translate(
                      offset: const Offset(10, -5),
                      child: IconButton(
                        icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 30),
                        onPressed: () {
                          SystemDialog.show(
                            context,
                            title: "ABANDON",
                            message: "La fuite entraînera une lourde pénalité d'XP. Confirmer ?",
                            isWarning: true,
                            color: Colors.redAccent,
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent.withOpacity(0.3),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  side: const BorderSide(color: Colors.redAccent),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  game.leaveDungeon();
                                },
                                child: const Text("FUIR", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("BOSS DU DONJON", style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          Text("${currentHp.toInt()} / ${maxHp.toInt()} PV", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          Container(height: 12, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                          LayoutBuilder(builder: (context, constraints) {
                            return Container(
                              height: 12,
                              width: constraints.maxWidth * hpPercent,
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.8), blurRadius: 10)],
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: d.tasks.length,
              itemBuilder: (ctx, i) {
                final task = d.tasks[i];
                final progress = d.progress[i];
                final amount = task['amount'] as num;
                double percent = (amount > 0) ? (progress / amount).clamp(0.0, 1.0) : 0.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: themeColor.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(task['title'].toString().toUpperCase(), style: GoogleFonts.rajdhani(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                          Text("${progress.toInt()} / ${amount.toInt()}", style: GoogleFonts.orbitron(color: themeColor, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Stack(
                        children: [
                          Container(height: 8, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                          LayoutBuilder(builder: (context, constraints) {
                            return Container(
                              height: 8,
                              width: constraints.maxWidth * percent,
                              decoration: BoxDecoration(
                                color: themeColor,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [BoxShadow(color: themeColor.withOpacity(0.6), blurRadius: 10)],
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    Vibration.vibrate(duration: 50);
                    game.trainAllManualExercises();
                  },
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      border: Border.all(color: themeColor, width: 2),
                      color: themeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: themeColor.withOpacity(0.3), blurRadius: 15)],
                    ),
                    child: Center(
                      child: Text("VALIDER L'EFFORT (+5 REPS)", style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: () => _makeEmergencyCall(context),
                        icon: const Icon(Icons.call, color: Colors.orange, size: 14),
                        label: const Text("APPEL", style: TextStyle(color: Colors.orange, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: () => _sendEmergencySMS(context),
                        icon: const Icon(Icons.message, color: Colors.orange, size: 14),
                        label: const Text("MESSAGE", style: TextStyle(color: Colors.orange, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00E5FF)),
                          backgroundColor: const Color(0xFF00E5FF).withOpacity(0.08),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: () => _showAmnestyConfirmDialog(context, game),
                        icon: const Icon(Icons.shield_moon_outlined, color: Color(0xFF00E5FF), size: 14),
                        label: const Text("AMNISTIE", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}