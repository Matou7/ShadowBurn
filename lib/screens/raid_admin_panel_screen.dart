import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/lan_socket_service.dart';
import '../services/raid_admin_service.dart';

const Color kSystemOrange = Color(0xFFFF9100);
const Color kSystemBlue = Color(0xFF00E5FF);

class RaidAdminPanelScreen extends StatefulWidget {
  final String roomId;
  final String adminKey;
  final String mode;
  final String? wsUrl;

  const RaidAdminPanelScreen({
    super.key,
    required this.roomId,
    required this.adminKey,
    this.mode = 'cloud',
    this.wsUrl,
  });

  bool get isLanMode =>
      mode.trim().toLowerCase() == 'lan' ||
      (wsUrl != null && wsUrl!.trim().isNotEmpty);

  @override
  State<RaidAdminPanelScreen> createState() => _RaidAdminPanelScreenState();
}

class _RaidAdminPanelScreenState extends State<RaidAdminPanelScreen> {
  bool _isChecking = true;
  bool _isAuthorized = false;
  String _denialReason = "VÉRIFICATION DES HAUTES PRIVILÈGES DU MONARQUE...";
  Map<String, dynamic> _raidData = {};
  StreamSubscription? _subscription;
  StreamSubscription>? _lanSubscription;
  final LanSocketService _lanSocket = LanSocketService();
  String? _lastErrorBanner;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    if (widget.isLanMode) {
      await _initLanSession();
    } else {
      await _verifyCloudAccess();
    }
  }

  Future<void> _initLanSession() async {
    final String targetWs = (widget.wsUrl ?? '').trim();
    if (targetWs.isEmpty) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason = "URL WEBSOCKET LAN ABSENTE.";
        });
      }
      return;
    }

    final String cleanRoom =
        widget.roomId.trim().isEmpty ? 'LAN_1' : widget.roomId.trim();

    RaidAdminService.configureLan(
      wsUrl: targetWs,
      roomId: cleanRoom,
    );

    if (mounted) {
      setState(() {
        _isChecking = false;
        _isAuthorized = true;
        _raidData = {
          'status': 'waiting',
          'current_hp': 5000,
          'max_hp': 5000,
          'hunters': [],
        };
      });
    }

    _lanSubscription?.cancel();
    _lanSubscription = _lanSocket.messages.listen((msg) {
      if (!mounted) return;
      final String type = (msg['type'] ?? '').toString().toLowerCase();
      if (type == 'state' || msg.containsKey('current_hp')) {
        setState(() {
          _raidData = {
            ..._raidData,
            ...msg,
          };
        });
      }
    });

    await _lanSocket.connect(
      targetWs,
      roomId: cleanRoom,
      role: 'admin',
      clientId: 'admin_${DateTime.now().millisecondsSinceEpoch}',
      name: 'MONARQUE (LAN)',
    );
  }

  Future<void> _verifyCloudAccess() async {
    if (widget.adminKey.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason = "ACCÈS REFUSÉ : CLÉ MAÎTRE ABSENTE.";
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('current_raids')
          .doc(widget.roomId)
          .get();
      if (!doc.exists) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason = "SALLE INTROUVABLE : [${widget.roomId}] n'existe pas.";
          });
        }
        return;
      }

      final data = doc.data() ?? {};
      final expectedKey = (data['admin_key'] ?? '').toString().trim();

      if (expectedKey.isEmpty || expectedKey != widget.adminKey.trim()) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _isAuthorized = false;
            _denialReason = "CLÉ MAÎTRE INVALIDE OU EXPIRÉE.";
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = true;
          _raidData = data;
        });
        _startCloudListening();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAuthorized = false;
          _denialReason = "Erreur de liaison Firestore : $e";
        });
      }
    }
  }

  void _startCloudListening() {
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .collection('current_raids')
        .doc(widget.roomId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          _raidData = doc.data() ?? {};
        });
      }
    });
  }

  Future<void> _runCommand(Future<String?> Function() action) async {
    final String? err = await action();
    if (!mounted) return;
    setState(() {
      _lastErrorBanner = err;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _lanSubscription?.cancel();
    if (widget.isLanMode) {
      RaidAdminService.clearLan();
      unawaited(_lanSocket.disconnect());
    }
    super.dispose();
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
              CircularProgressIndicator(color: kSystemOrange),
              SizedBox(height: 16),
              Text(
                "SYNCHRONISATION DE LA TÉLÉCOMMANDE MAÎTRE...",
                style: TextStyle(
                  color: kSystemOrange,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
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
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _denialReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final String status = (_raidData['status'] ?? 'waiting').toString();
    final num currentHp = (_raidData['current_hp'] ?? 5000) as num;
    final num maxHp = (_raidData['max_hp'] ?? 5000) as num;
    final dynamic rawHunters = _raidData['hunters'];
    final List hunters = rawHunters is Iterable ? rawHunters.toList() : [];

    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04101E),
        title: Text(
          widget.isLanMode
              ? "TÉLÉCOMMANDE LAN : [${widget.roomId}]"
              : "TÉLÉCOMMANDE : SALLE [${widget.roomId}]",
          style: GoogleFonts.orbitron(
            color: kSystemOrange,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: kSystemOrange),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_lastErrorBanner != null && _lastErrorBanner!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A0710),
                  border: Border.all(color: const Color(0xFFFF2E56)),
                ),
                child: Text(
                  _lastErrorBanner!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF04101E),
                border: Border.all(color: kSystemOrange, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    widget.isLanMode
                        ? "LIAISON : ${widget.wsUrl ?? 'LAN'}"
                        : "LIAISON : CLOUD FIRESTORE",
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "STATUT DU DONJON : ${status.toUpperCase()}",
                    style: GoogleFonts.orbitron(
                      color: kSystemBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "PV DU BOSS : $currentHp / $maxHp",
                    style: GoogleFonts.orbitron(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Chasseurs connectés : ${hunters.length}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "GESTION DES PRÈSETS DE BOSS",
              style: GoogleFonts.orbitron(
                color: kSystemOrange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: RaidAdminService.raidPresets.map((preset) {
                final int hp = preset['hp'] as int;
                final String label = preset['label'] as String;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF04101E),
                    side: const BorderSide(color: kSystemOrange),
                  ),
                  onPressed: () => _runCommand(
                    () => RaidAdminService.applyPreset(
                      hp,
                      label,
                      roomId: widget.roomId,
                    ),
                  ),
                  child: Text(
                    "$label ($hp PV)",
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              "COMMANDES TACTIQUES",
              style: GoogleFonts.orbitron(
                color: kSystemOrange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF66),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _runCommand(
                      () => RaidAdminService.setRaidStatus(
                        'active',
                        roomId: widget.roomId,
                      ),
                    ),
                    child: const Text(
                      "LANCER",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9100),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _runCommand(
                      () => RaidAdminService.strikeBoss(
                        200,
                        roomId: widget.roomId,
                      ),
                    ),
                    child: const Text(
                      "-200 PV",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF2E56),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _runCommand(
                      () => RaidAdminService.resetBoss(roomId: widget.roomId),
                    ),
                    child: const Text(
                      "RESET",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "CONTRÔLE DU TEMPS",
              style: GoogleFonts.orbitron(
                color: kSystemOrange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kSystemBlue),
                    ),
                    onPressed: () => _runCommand(
                      () => RaidAdminService.extendRaidMinutes(
                        15,
                        roomId: widget.roomId,
                      ),
                    ),
                    child: const Text(
                      "+15 MIN",
                      style: TextStyle(color: kSystemBlue),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber),
                    ),
                    onPressed: () => _runCommand(
                      () => RaidAdminService.resetToMidnight(
                        roomId: widget.roomId,
                      ),
                    ),
                    child: const Text(
                      "RESET 24H",
                      style: TextStyle(color: Colors.amber),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFF2E56)),
                    ),
                    onPressed: () => _runCommand(
                      () => RaidAdminService.expireRaidNow(
                        roomId: widget.roomId,
                      ),
                    ),
                    child: const Text(
                      "CLÔTURER",
                      style: TextStyle(color: Color(0xFFFF2E56)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
