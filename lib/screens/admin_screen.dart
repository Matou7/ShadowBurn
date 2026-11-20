// lib/screens/admin_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/quota_guard_service.dart';

const Color kSystemBlue = Color(0xFF00E5FF);

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late String _roomId;
  late String _key;
  late String _token;
  bool _attemptedAutoLaunch = false;
  bool _isChecking = true;
  bool _isAuthorized = false;
  String _denialReason = "VÉRIFICATION DES DROITS DU MONARQUE...";

  static final String _adminSessionId =
      'admin_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = Uri.base;
    String? roomParam = uri.queryParameters['room'];
    String? keyParam = uri.queryParameters['key'];
    String? tokenParam = uri.queryParameters['token'];

    if (uri.fragment.contains('?')) {
      final fragmentParams = Uri.splitQueryString(uri.fragment.split('?').last);
      roomParam ??= fragmentParams['room'];
      keyParam ??= fragmentParams['key'];
      tokenParam ??= fragmentParams['token'];
    }

    _roomId = (roomParam != null && roomParam.trim().isNotEmpty)
        ? roomParam.trim()
        : 'room_1';
    _key = (keyParam ?? '').trim();
    _token = (tokenParam ?? '').trim();

    _verifyAdminAccess();
  }

  Future<void> _verifyAdminAccess() async {
    if (_key.isEmpty && _token.isEmpty) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason =
              "ACCÈS REFUSÉ : AUCUNE CLÉ MAÎTRE OU TOKEN DÉTECTÉ.\nLe mode télécommande requiert un lien de salle valide.";
        });
      }
      return;
    }

    try {
      final ref = FirebaseFirestore.instance.collection('current_raids').doc(_roomId);
      final doc = await ref.get();
      if (!doc.exists) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason = "SALLE INTROUVABLE : La salle [$_roomId] n'existe pas.";
          });
        }
        return;
      }

      final data = doc.data() as Map<String, dynamic>? ?? {};
      final String expectedKey = (data['admin_key'] ?? '').toString().trim();
      final String expectedToken = (data['join_token'] ?? '').toString().trim();

      final bool keyMatches = _key.isNotEmpty && expectedKey == _key;
      final bool tokenMatches = _token.isNotEmpty && expectedToken == _token;

      if (!keyMatches && !tokenMatches) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "ACCÈS REFUSÉ : CLÉ OU TOKEN INVALIDE POUR LA SALLE [$_roomId].";
          });
        }
        return;
      }

      final String? activeAdmin = data['active_admin_session'];
      final int lastAdminHeartbeat = (data['admin_last_seen'] as num?)?.toInt() ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;

      if (activeAdmin != null &&
          activeAdmin != _adminSessionId &&
          (now - lastAdminHeartbeat < 60000)) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "ACCÈS BLOQUÉ : UNE SESSION ADMINISTRATEUR EST DÉJÀ ACTIVE SUR UN AUTRE APPAREIL.";
          });
        }
        return;
      }

      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason =
                "QUOTA DE SÉCURITÉ ATTEINT.\nAccès administrateur suspendu temporairement.";
          });
        }
        return;
      }

      await ref.set({
        'active_admin_session': _adminSessionId,
        'admin_last_seen': now,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = true;
        });

        if (!_attemptedAutoLaunch) {
          _attemptedAutoLaunch = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _launchNativeApp();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason = "Erreur de communication avec le portail : $e";
        });
      }
    }
  }

  Future<void> _toggleRemoteAudio() async {
    if (_roomId.isEmpty) return;
    try {
      bool canWrite = await QuotaGuardService.checkAndIncrementWrite();
      if (!canWrite) return;

      final ref = FirebaseFirestore.instance.collection('current_raids').doc(_roomId);
      final doc = await ref.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        bool currentAudio = data['audio_playing'] == true;
        await ref.update({'audio_playing': !currentAudio});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(!currentAudio
                  ? "[RADIO] Ordre d'activation envoyé à la TV"
                  : "[RADIO] Ordre de pause envoyé à la TV"),
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Erreur bascule audio distante: $e");
    }
  }

  Future<void> _launchNativeApp() async {
    final String customSchemeUrl =
        "shadowburn://admin?room=$_roomId&key=$_key&token=$_token";

    try {
      final schemeUri = Uri.parse(customSchemeUrl);
      await launchUrl(schemeUri, mode: LaunchMode.externalNonBrowserApplication);
    } catch (e) {
      debugPrint("Erreur ouverture app native: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070D),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF9100)),
              SizedBox(height: 16),
              Text(
                "CONTRÔLE DU STATUT DU MAÎTRE...",
                style: TextStyle(
                    color: Color(0xFFFF9100),
                    fontFamily: 'monospace',
                    letterSpacing: 2),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF04101E),
                border: Border.all(color: const Color(0xFFFF2E56), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_bad, color: Color(0xFFFF2E56), size: 54),
                  const SizedBox(height: 16),
                  const Text(
                    "CONTRÔLE MAÎTRE BLOQUÉ",
                    style: TextStyle(
                        color: Color(0xFFFF2E56),
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _denialReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF04101E),
                border: Border.all(color: const Color(0xFFFF9100), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.security, color: Color(0xFFFF9100), size: 44),
                  const SizedBox(height: 14),
                  const Text(
                    "CONTRÔLE MAÎTRE DU JEU",
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "SALLE : $_roomId",
                    style: const TextStyle(
                        color: Color(0xFFFF9100),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Ouverture automatique vers l'application ShadowBurn avec liaison de salle active.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9100),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const BeveledRectangleBorder(),
                      ),
                      icon: const Icon(Icons.phone_android,
                          color: Colors.black, size: 20),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "OUVRIR DANS L'APPLICATION",
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              fontSize: 12),
                        ),
                      ),
                      onPressed: _launchNativeApp,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const BeveledRectangleBorder(),
                      ),
                      icon: const Icon(Icons.volume_up,
                          color: Colors.black, size: 20),
                      label: const Text(
                        "BASCULER LA RADIO (TV)",
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontSize: 12),
                      ),
                      onPressed: _toggleRemoteAudio,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "Token : ${_token.isNotEmpty ? _token : "aucun"} | Clé : ${_key.isNotEmpty ? _key : "aucune"}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Télécommande native intégrée dans l'application Android, liée directement à la salle (ex: room_1).
class NativeRemoteControlScreen extends StatefulWidget {
  final String roomId;
  final String adminKey;
  final String joinToken;

  const NativeRemoteControlScreen({
    super.key,
    required this.roomId,
    this.adminKey = '',
    this.joinToken = '',
  });

  @override
  State<NativeRemoteControlScreen> createState() =>
      _NativeRemoteControlScreenState();
}

class _NativeRemoteControlScreenState extends State<NativeRemoteControlScreen> {
  late DocumentReference> _raidRef;

  @override
  void initState() {
    super.initState();
    _raidRef = FirebaseFirestore.instance
        .collection('current_raids')
        .doc(widget.roomId);
  }

  Future<void> _setRaidStatus(String status) async {
    final canWrite = await QuotaGuardService.checkAndIncrementWrite();
    if (!canWrite) return;
    await _raidRef.update({'status': status}).catchError((_) {});
  }

  Future<void> _toggleAudio(bool currentPlaying) async {
    final canWrite = await QuotaGuardService.checkAndIncrementWrite();
    if (!canWrite) return;
    await _raidRef.update({'audio_playing': !currentPlaying}).catchError((_) {});
  }

  Future<void> _resetBoss() async {
    final canWrite = await QuotaGuardService.checkAndIncrementWrite();
    if (!canWrite) return;
    await _raidRef.update({
      'current_hp': 5000,
      'max_hp': 5000,
      'status': 'waiting',
      'logs': [],
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04101E),
        title: Text(
          "TÉLÉCOMMANDE [${widget.roomId}]",
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFFFF9100),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>>(
        stream: _raidRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9100)),
            );
          }

          if (!snapshot.data!.exists) {
            return Center(
              child: Text(
                "SALLE [${widget.roomId}] INACTIVE OU FERMÉE",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFFF2E56),
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          final data = snapshot.data!.data() ?? {};
          final String status = (data['status'] ?? 'waiting').toString();
          final int hp = (data['current_hp'] as num?)?.toInt() ?? 5000;
          final int maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;
          final bool audioPlaying = data['audio_playing'] == true;
          final List hunters =
              data['hunters'] is Iterable ? (data['hunters'] as Iterable).toList() : [];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF04101E),
                    border: Border.all(color: const Color(0xFFFF9100), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "SALLE LIÉE : ${widget.roomId}",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFFF9100),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "STATUT : ${status.toUpperCase()} | BOSS : $hp / $maxHp PV",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "CHASSEURS CONNECTÉS : ${hunters.length}",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF00E5FF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF66),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _setRaidStatus('active'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    "DÉMARRER LE RAID",
                    style: TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9100),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _setRaidStatus('waiting'),
                  icon: const Icon(Icons.pause),
                  label: const Text(
                    "METTRE EN ATTENTE (LOBBY)",
                    style: TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _toggleAudio(audioPlaying),
                  icon: Icon(audioPlaying ? Icons.volume_off : Icons.volume_up),
                  label: Text(
                    audioPlaying ? "COUPER RADIO TV" : "ACTIVER RADIO TV",
                    style: const TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF2E56),
                    side: const BorderSide(color: Color(0xFFFF2E56)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _resetBoss,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    "RÉINITIALISER BOSS (5 000 PV)",
                    style: TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
