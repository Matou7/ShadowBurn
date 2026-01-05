import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/game_provider.dart';
import '../widgets/system_dialog.dart';
import '../utils/admin_utils.dart'; // Nécessaire pour le mot de passe

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // --- RÉDUCTION DE LA PRÉCISION POUR ÉVITER LES DÉBORDEMENTS ---
  String _formatStat(int value) {
    if (value >= 1000000) return "${(value / 1000000).toStringAsFixed(1)}M";
    if (value >= 1000) return "${(value / 1000).toStringAsFixed(1)}K";
    return value.toString();
  }

  String _formatDate(String isoDate) {
    DateTime dt = DateTime.parse(isoDate);
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    const Color systemBlue = Color(0xFF00E5FF);
    final Color borderBlue = systemBlue.withOpacity(0.5);

    // Couleur dynamique du Rang : Rouge si God Mode actif, Blanc sinon
    final Color rankColor = game.isGodMode ? Colors.redAccent : Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF001122)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
          child: Column(
            children: [
              // --- CARD DE STATUT ---
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: borderBlue, width: 2),
                  color: Colors.black.withOpacity(0.7),
                  boxShadow: [BoxShadow(color: systemBlue.withOpacity(0.15), blurRadius: 20)],
                ),
                child: Column(
                  children: [
                    _buildSectionHeader("STATUT", systemBlue),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20.0),
                      child: Column(
                        children: [
                          // --- AJOUT : PSEUDO DU CHASSEUR ---
                          GestureDetector(
                            onLongPress: () => _showEditUsernameDialog(context, game),
                            child: Text(
                              game.username.toUpperCase(),
                              style: GoogleFonts.orbitron(
                                color: systemBlue,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                                shadows: [Shadow(color: systemBlue.withOpacity(0.5), blurRadius: 10)],
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // --- TRIGGER GOD MODE (LETTRE RANG) ---
                              GestureDetector(
                                onLongPress: () {
                                  if (game.isGodMode) {
                                    SystemDialog.show(
                                      context,
                                      title: "SYSTÈME ADMIN",
                                      message: "Désactiver le God Mode et revenir à la normale ?",
                                      color: Colors.redAccent,
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          onPressed: () {
                                            game.setGodMode(false);
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("God Mode Désactivé.")));
                                          }, 
                                          child: const Text("DÉSACTIVER")
                                        ),
                                      ]
                                    );
                                  } else {
                                    showAdminAuthDialog(context, game);
                                  }
                                },
                                child: Text(game.rank, 
                                  style: GoogleFonts.orbitron(
                                    color: rankColor, 
                                    fontSize: 60, 
                                    fontWeight: FontWeight.bold, 
                                    shadows: [
                                      const Shadow(color: systemBlue, blurRadius: 10),
                                      Shadow(color: systemBlue.withOpacity(0.8), blurRadius: 30),
                                      if (game.isGodMode) const Shadow(color: Colors.red, blurRadius: 50),
                                    ]
                                  )
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text("RANG", style: GoogleFonts.orbitron(color: systemBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          if (game.isGodMode)
                            Text("[ GOD MODE ACTIF ]", style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 10, letterSpacing: 2)),
                          
                          Text("TITRE: ${game.equippedTitle.toUpperCase()}", 
                            style: GoogleFonts.rajdhani(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          const SizedBox(height: 10),
                          _buildGoldBadge(game, context),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          _buildStatusLine("PV", game.currentHealth, game.maxHealth, systemBlue, context, isEditable: true, game: game, stat: "HP"),
                          const SizedBox(height: 15),
                          _buildStatusLine("XP", game.currentXP.toInt(), game.nextRankThreshold.toInt(), const Color(0xFFD500F9), context, isEditable: true, game: game, stat: "XP"),
                          const SizedBox(height: 10),
                          _buildSurpassement(game.totalSurpassement),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    _buildAttributesGrid(context, game),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              Text("HISTORIQUE DE DÉVELOPPEMENT", style: GoogleFonts.orbitron(color: systemBlue, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _buildHeatMap(game, context), 

              const SizedBox(height: 35),
              if (game.saveHistory.isNotEmpty) ...[
                _buildArchiveList(context, game, systemBlue),
              ],
              const SizedBox(height: 20),
              _buildSystemButtons(context, game, systemBlue),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- LOGIQUE DE MODIFICATION DU PSEUDO ---
  void _showEditUsernameDialog(BuildContext context, GameProvider game) {
    final controller = TextEditingController(text: game.username);
    SystemDialog.show(
      context,
      title: "IDENTITÉ",
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: "Nouveau pseudo", 
          hintStyle: TextStyle(color: Colors.white24)
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              game.updateUsername(controller.text);
            }
            Navigator.pop(context);
          }, 
          child: const Text("VALIDER")
        ),
      ]
    );
  }

  Widget _buildGoldBadge(GameProvider game, BuildContext context) {
    return GestureDetector(
      onTap: () => _showShopDialog(context, game),
      onLongPress: game.isGodMode ? () => _showEditStatDialog(context, game, "OR") : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFFD700)), 
          borderRadius: BorderRadius.circular(4), 
          color: const Color(0xFFFFD700).withOpacity(0.05)
        ),
        child: Text("OR: ${game.goldCoins}", style: GoogleFonts.orbitron(color: const Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildAttributesGrid(BuildContext context, GameProvider game) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 15,
        runSpacing: 20, 
        children: [
          _buildEditableAttribute(context, game, "POMPES", _formatStat(game.totalPompes)), 
          _buildEditableAttribute(context, game, "ABDOS", _formatStat(game.totalAbdos)),      
          _buildEditableAttribute(context, game, "SQUATS", _formatStat(game.totalSquats)), 
          _buildEditableAttribute(context, game, "ENDURANCE", "${game.totalKm.toStringAsFixed(1)} KM"), 
          _buildEditableAttribute(context, game, "DISCIPLINE", game.currentStreak.toString()), 
        ],
      ),
    );
  }

  Widget _buildEditableAttribute(BuildContext context, GameProvider game, String label, String value) {
    return GestureDetector(
      onLongPress: game.isGodMode ? () => _showEditStatDialog(context, game, label) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_box_outlined, color: game.isGodMode ? Colors.redAccent : const Color(0xFF00E5FF), size: 14),
          const SizedBox(width: 5),
          Text("$label: ", style: GoogleFonts.orbitron(color: const Color(0xFF00E5FF), fontSize: 11)),
          Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showEditStatDialog(BuildContext context, GameProvider game, String label) {
    final controller = TextEditingController();
    SystemDialog.show(
      context,
      title: "MODIFIER $label",
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: "Nouvelle valeur", 
          hintStyle: TextStyle(color: Colors.white24)
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
        TextButton(onPressed: () {
          double? val = double.tryParse(controller.text);
          if (val != null) {
              game.updateTotalStat(label, val);
          }
          Navigator.pop(context);
        }, child: const Text("VALIDER")),
      ]
    );
  }

  Widget _buildHeatMap(GameProvider game, BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      padding: const EdgeInsets.all(4), 
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24, width: 1), 
        color: Colors.white.withOpacity(0.02)
      ),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 14, 
          crossAxisSpacing: 3, 
          mainAxisSpacing: 3, 
          childAspectRatio: 1.0
        ),
        itemCount: 70,
        itemBuilder: (context, index) {
          final dateToShow = today.subtract(Duration(days: 69 - index));
          final dateKey = dateToShow.toIso8601String().split('T')[0];
          Map<String, dynamic>? data = game.calendarHistory[dateKey];
          Color boxColor = const Color(0xFF1A1A2E); 
          if (data != null) {
            if (data['status'] == 'gold') boxColor = const Color(0xFFFFD700);
            else if (data['status'] == 'blue') boxColor = const Color(0xFF00E5FF);
          } 
          return GestureDetector(
            onLongPress: game.isGodMode ? () => _showEditHistoryDialog(context, game, dateKey) : null,
            child: Container(
              decoration: BoxDecoration(
                color: boxColor, 
                borderRadius: BorderRadius.circular(1),
                border: (index == 69) ? Border.all(color: Colors.white30, width: 1) : null
              )
            )
          );
        },
      ),
    );
  }
  
  void _showEditHistoryDialog(BuildContext context, GameProvider game, String dateKey) {
      SystemDialog.show(
        context,
        title: "MODIFICATION : $dateKey",
        content: const Text("Modifier l'état de ce jour ?", style: TextStyle(color: Colors.white70)),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                onPressed: () {
                    game.deleteHistoryEntry(dateKey);
                    Navigator.pop(context);
                },
              ),
              InkWell(
                onTap: () {
                    game.updateHistoryStatus(dateKey, 'blue');
                    Navigator.pop(context);
                },
                child: Container(width: 30, height: 30, color: const Color(0xFF00E5FF)),
              ),
              InkWell(
                onTap: () {
                    game.updateHistoryStatus(dateKey, 'gold');
                    Navigator.pop(context);
                },
                child: Container(width: 30, height: 30, color: const Color(0xFFFFD700)),
              ),
              InkWell(
                onTap: () {
                    game.updateHistoryStatus(dateKey, 'grey');
                    Navigator.pop(context);
                },
                child: Container(width: 30, height: 30, color: const Color(0xFF1A1A2E)),
              ),
            ]
          )
        ]
      );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color.withOpacity(0.5)))),
      child: Center(child: Text(title, style: GoogleFonts.orbitron(color: color, fontSize: 20, letterSpacing: 10, fontWeight: FontWeight.bold))),
    );
  }

  Widget _buildStatusLine(String label, int val, int max, Color color, BuildContext context, {bool isEditable = false, GameProvider? game, String? stat}) {
    double progress = (max > 0) ? (val / max).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      onLongPress: (isEditable && game != null && game.isGodMode) 
          ? () => _showEditStatDialog(context, game, stat ?? label) 
          : null,
      child: Row(
        children: [
          SizedBox(width: 35, child: Text(label, style: GoogleFonts.orbitron(color: color, fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(height: 10, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                    Container(
                      height: 10, 
                      width: constraints.maxWidth * progress, 
                      decoration: BoxDecoration(
                        color: color, 
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 5)]
                      )
                    ),
                  ],
                );
              }
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              "${_formatStat(val)}/${_formatStat(max)}", 
              textAlign: TextAlign.right,
              style: GoogleFonts.rajdhani(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurpassement(int value) {
    String displayValue = value.toString();
    if (value >= 1000) {
      displayValue = "${(value / 1000).toStringAsFixed(1)} K";
    }
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      const Icon(Icons.bolt, color: Colors.yellowAccent, size: 16),
      const SizedBox(width: 5),
      Text(
        "SURPASSEMENT: $displayValue", 
        style: GoogleFonts.orbitron(
            color: Colors.cyanAccent, 
            fontSize: 11, 
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            shadows: [const Shadow(color: Colors.cyan, blurRadius: 5)]
        )
      ),
    ]);
  }

  Widget _buildArchiveList(BuildContext context, GameProvider game, Color systemBlue) {
    return Column(
      children: [
        Text("ARCHIVES DU SYSTÈME", style: GoogleFonts.orbitron(color: systemBlue, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: game.saveHistory.length,
          itemBuilder: (ctx, i) {
            final item = game.saveHistory[i];
            return ListTile(
              title: Text("Séquence du ${_formatDate(item['date'])}", style: GoogleFonts.rajdhani(color: Colors.white)),
              trailing: const Icon(Icons.copy, color: Colors.white24, size: 16),
              onTap: () {
                Clipboard.setData(ClipboardData(text: item['code']));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copié !")));
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSystemButtons(BuildContext context, GameProvider game, Color color) {
    return Row(children: [
      Expanded(child: _holoButton("EXPORTER", color, () {
        Clipboard.setData(ClipboardData(text: game.exportSaveCode()));
      })),
      const SizedBox(width: 15),
      Expanded(child: _holoButton("IMPORTER", Colors.redAccent, () => _showImportDialog(context, game))),
    ]);
  }

  Widget _holoButton(String text, Color color, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(side: BorderSide(color: color.withOpacity(0.5))),
      child: Text(text, style: GoogleFonts.orbitron(color: color, fontSize: 10)),
    );
  }

  void _showImportDialog(BuildContext context, GameProvider game) {
    final controller = TextEditingController();
    SystemDialog.show(context, title: "SYNCHRONISATION", content: TextField(controller: controller, style: const TextStyle(color: Colors.white)), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER")),
      TextButton(onPressed: () { game.importSaveCode(controller.text); Navigator.pop(context); }, child: const Text("VALIDER")),
    ]);
  }

  void _showShopDialog(BuildContext context, GameProvider game) {
    SystemDialog.show(context, title: "BOUTIQUE", content: Column(mainAxisSize: MainAxisSize.min, children: [
      _buildShopItem(context, game, "Potion Mineure", "Soigne 50 PV", game.priceMinorPotion, "mineure"),
      _buildShopItem(context, game, "Potion Majeure", "Soigne 200 PV", game.priceMajorPotion, "majeure"),
      _buildShopItem(context, game, "Élixir Royal", "Soigne tout", game.priceFullHeal, "guérison"),
    ]), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("RETOUR"))
    ]);
  }

  Widget _buildShopItem(BuildContext ctx, GameProvider game, String name, String desc, int price, String id) {
    return ListTile(
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(desc, style: const TextStyle(color: Colors.grey)),
      trailing: TextButton(
        onPressed: () {
          if (game.currentHealth >= game.maxHealth) {
             ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Santé déjà au maximum."), backgroundColor: Colors.blueAccent));
             return;
          }
          bool success = game.buyItem(id);
          if (success) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Achat effectué."), duration: Duration(seconds: 1)));
          } else {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Fonds insuffisants."), backgroundColor: Colors.red));
          }
        }, 
        child: Text("$price Or", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))
      ),
    );
  }
}