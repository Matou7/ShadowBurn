// lib/screens/stats_quests_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../providers/game_provider.dart';
import '../widgets/system_dialog.dart';
import 'class_change_quest_screen.dart';

class StatsQuestsScreen extends StatefulWidget {
  const StatsQuestsScreen({super.key});

  @override
  State<StatsQuestsScreen> createState() => _StatsQuestsScreenState();
}

class _StatsQuestsScreenState extends State<StatsQuestsScreen> {
  Timer? _timer;
  late int _secondsRemaining;
  String _cachedShortKey = '';

  @override
  void initState() {
    super.initState();
    _calculateTimeUntilMidnight();
    _startTimer();
    _loadCachedLicense();
  }

  Future<void> _loadCachedLicense() async {
    final prefs = await SharedPreferences.getInstance();
    final fullKey = prefs.getString('shadow_user_license_key') ?? '';
    if (fullKey.isNotEmpty && mounted) {
      setState(() {
        _cachedShortKey = _formatShortKey(fullKey);
      });
    }
  }

  String _formatShortKey(String raw) {
    String clean = raw.trim().toUpperCase();
    if (clean.contains('-')) {
      final parts = clean.split('-');
      if (parts.length >= 2) {
        return "${parts[parts.length - 2]}-${parts[parts.length - 1]}";
      }
    }
    return clean.length > 9 ? clean.substring(clean.length - 9) : clean;
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
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            _calculateTimeUntilMidnight();
          }
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

  void _showEditDailyStatDialog(BuildContext context, GameProvider game, String label, dynamic currentValue) {
    final controller = TextEditingController(text: currentValue.toString());
    final String statKey = label.toLowerCase();

    SystemDialog.show(
      context,
      title: "GOD MODE: $label",
      content: TextField(
        controller: controller,
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
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () {
            num? newVal = num.tryParse(controller.text.replaceAll(',', '.'));
            if (newVal != null) {
              if (statKey.contains("course") || statKey.contains("km")) {
                game.setDailyKm(newVal.toDouble());
              } else {
                game.setDailyStat(statKey, newVal);
              }
            }
            Navigator.pop(context);
          },
          child: const Text("MODIFIER", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<String> _getLocalHardwareId(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String? hw = prefs.getString('shadow_hardware_fingerprint');
    if (hw == null || hw.isEmpty) {
      final width = MediaQuery.sizeOf(context).width.toInt();
      hw = 'hw_sig_${width}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('shadow_hardware_fingerprint', hw);
    }
    return hw;
  }

  Future<void> _launchDynamicStripeCheckout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text("Génération du portail de paiement sécurisé..."), duration: Duration(seconds: 2)),
    );

    try {
      final String hardwareId = await _getLocalHardwareId(context);
      
      final response = await http.post(
        Uri.parse('https://shadowburn-webhook.onrender.com/api/create-checkout-session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'hardware_id': hardwareId,
          'success_url': 'shadowburn://pro-success',
          'cancel_url': 'shadowburn://pro-cancel',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? checkoutUrl = data['url'];
        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          final Uri uri = Uri.parse(checkoutUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text("Erreur de connexion au serveur de paiement."), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Exception Stripe : $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showProActivationDialog(BuildContext context, GameProvider game) {
    final controller = TextEditingController();
    SystemDialog.show(
      context,
      title: "PASS PRO MONARQUE",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Obtenez le Pass Pro pour déverrouiller l'hébergement multijoueur (Arène TV), la télécommande et tous les donjons d'élite.",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Entrez votre clé Pro (ex: SHADOW-PRO-XXXX-YYYY)",
              hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFD700),
                side: const BorderSide(color: Color(0xFFFFD700)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              icon: const Icon(Icons.payment, size: 16),
              label: const Text("COMMANDER LE PASS PRO (14,99 €)", style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
              onPressed: () {
                Navigator.pop(context);
                _launchDynamicStripeCheckout(context);
              },
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              game.showOtpRecoveryDialog(context);
            },
            child: const Text(
              "Déjà acheté ? Restaurer avec votre email",
              style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      color: const Color(0xFFFFD700),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("RETOUR")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700).withOpacity(0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: const BorderSide(color: Color(0xFFFFD700)),
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final keyInput = controller.text.trim();
            Navigator.pop(context);

            final bool success = await game.activateProKey(keyInput);
            if (success) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('shadow_user_license_key', keyInput);
              if (mounted) {
                setState(() {
                  _cachedShortKey = _formatShortKey(keyInput);
                });
              }
            }

            messenger.showSnackBar(
              SnackBar(
                content: Text(success ? "Éveil réussi ! Bienvenue, Monarque." : "Clé invalide, expirée ou déjà consommée."),
                backgroundColor: success ? Colors.green : Colors.redAccent,
              ),
            );
          },
          child: const Text("ACTIVER", style: TextStyle(color: Colors.white)),
        ),
      ],
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
    const Color systemBlue = Color(0xFF00E5FF);

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: systemBlue.withOpacity(0.5), width: 2),
            color: Colors.black.withOpacity(0.8),
            boxShadow: [BoxShadow(color: systemBlue.withOpacity(0.15), blurRadius: 30)],
          ),
          child: Column(
            children: [
              _buildQuestHeader(systemBlue, game),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: systemBlue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: systemBlue.withOpacity(0.2)),
                        ),
                        child: Text(
                          _formatDuration(_secondsRemaining),
                          style: GoogleFonts.orbitron(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              const Shadow(color: systemBlue, blurRadius: 15),
                              Shadow(color: systemBlue.withOpacity(0.5), blurRadius: 30),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        "[Quête Quotidienne : Préparation à la force.]",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic),
                      ),
                      Column(
                        children: [
                          Text("OBJECTIF", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 5)),
                          const SizedBox(height: 4),
                          Container(width: 60, height: 2, color: Colors.white38),
                        ],
                      ),
                      Column(
                        children: [
                          _buildQuestGoal(context, game, "Pompes", game.pompesDone, game.goalPompes, systemBlue),
                          _buildQuestGoal(context, game, "Abdos", game.abdosDone, game.goalAbdos, systemBlue),
                          _buildQuestGoal(context, game, "Squats", game.squatsDone, game.goalSquats, systemBlue),
                          _buildQuestGoal(
                            context,
                            game,
                            "Course",
                            game.kmCycleCurrent,
                            game.goalKm,
                            systemBlue,
                            isKm: true,
                            onRunToggle: () => game.toggleRunTracking(),
                            isTracking: game.isTrackingRun,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _actionButton("POMPES", () => game.addReps("Pompes", 5), systemBlue),
                          _actionButton("ABDOS", () => game.addReps("Abdos", 5), systemBlue),
                          _actionButton("SQUATS", () => game.addReps("Squats", 5), systemBlue),
                        ],
                      ),
                      if (game.isClassChangeAvailable || game.isClassChangeActive)
                        _holoButton(
                          game.isClassChangeActive ? "ÉPREUVE EN COURS" : "DÉFI DE CLASSE",
                          Colors.deepPurpleAccent,
                          () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ClassChangeQuestScreen())),
                        ),
                      Text(
                        "ATTENTION : L'échec de la quête entraînera une pénalité.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(color: Colors.redAccent.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
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

  Widget _buildQuestHeader(Color color, GameProvider game) {
    final String displayKey = _cachedShortKey.isNotEmpty
        ? _cachedShortKey
        : (game.shortLicenseKey.isNotEmpty ? game.shortLicenseKey : "MONARQUE");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color.withOpacity(0.5)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: color, size: 20),
              const SizedBox(width: 6),
              Text("INFOS QUÊTE", style: GoogleFonts.orbitron(color: color, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
            ],
          ),
          if (!game.isPro)
            InkWell(
              onTap: () => _showProActivationDialog(context, game),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFFFD700)),
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("PASS PRO", style: GoogleFonts.orbitron(color: const Color(0xFFFFD700), fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            )
          else
            InkWell(
              onTap: () {
                if (_cachedShortKey.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: _cachedShortKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Clé copiée : $_cachedShortKey"),
                      duration: const Duration(seconds: 1),
                      backgroundColor: Colors.amber[800],
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber),
                  color: Colors.amber.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user, color: Colors.amber, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      displayKey,
                      style: GoogleFonts.orbitron(
                        color: Colors.amber,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestGoal(
    BuildContext context,
    GameProvider game,
    String title,
    dynamic current,
    dynamic goal,
    Color color, {
    bool isKm = false,
    VoidCallback? onRunToggle,
    bool isTracking = false,
  }) {
    bool isDone = current >= goal;
    String currentStr = isKm ? (current as double).toStringAsFixed(1) : current.toString();
    String goalStr = isKm ? "${(goal as double).toStringAsFixed(1)}km" : goal.toString();

    return GestureDetector(
      onLongPress: () {
        if (game.isGodMode) {
          _showEditDailyStatDialog(context, game, title, current);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (game.isGodMode)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.edit, size: 12, color: Colors.redAccent),
                    ),
                  if (isKm) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onRunToggle,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          isTracking ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: color,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              "[$currentStr / $goalStr]",
              style: GoogleFonts.orbitron(
                color: isDone ? color : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isDone ? Icons.check_box : Icons.check_box_outline_blank,
              color: isDone ? color : Colors.white24,
              size: 18,
            ),
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
          borderRadius: BorderRadius.circular(4),
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
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: Text(text, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2))),
      ),
    );
  }
}
