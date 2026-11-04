import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/arena_backend_service.dart';
import '../services/raid_admin_service.dart';

class RaidAdminPanelScreen extends StatefulWidget {
  const RaidAdminPanelScreen({
    super.key,
    required this.roomId,
    required this.adminKey,
  });

  final String roomId;
  final String adminKey;

  @override
  State<RaidAdminPanelScreen> createState() => _RaidAdminPanelScreenState();
}

class _RaidAdminPanelScreenState extends State<RaidAdminPanelScreen> {
  bool _checking = true;
  bool _authorized = false;
  bool _busy = false;
  String _message = 'VALIDATION DU SCEAU MONARQUE...';

  DocumentReference<Map<String, dynamic>> get _roomRef =>
      FirebaseFirestore.instance.collection('current_raids').doc(widget.roomId);

  @override
  void initState() {
    super.initState();
    _validateKey();
  }

  Future<void> _validateKey() async {
    try {
      final valid = await ArenaBackendService.verifyAdminKey(
        roomId: widget.roomId,
        adminKey: widget.adminKey,
      );
      if (!mounted) return;
      setState(() {
        _authorized = valid;
        _checking = false;
        _message = valid ? 'LIAISON MONARQUE VALIDÉE' : 'CLÉ MONARQUE REFUSÉE';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _checking = false;
        _message = 'VALIDATION SERVEUR IMPOSSIBLE : $error';
      });
    }
  }

  Future<void> _execute(
    String label,
    Future<void> Function() operation,
  ) async {
    if (_busy || !_authorized) return;
    setState(() {
      _busy = true;
      _message = 'EXÉCUTION : $label';
    });
    try {
      await operation();
      if (!mounted) return;
      setState(() => _message = 'COMMANDE VALIDÉE : $label');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'COMMANDE REFUSÉE : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04101E),
        title: const Text(
          'TÉLÉCOMMANDE MONARQUE',
          style: TextStyle(
            color: Color(0xFFFF9100),
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9100)))
          : !_authorized
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFF2E56), fontFamily: 'monospace'),
                    ),
                  ),
                )
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _roomRef.snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() ?? <String, dynamic>{};
                    final hp = (data['current_hp'] as num?)?.toInt() ?? 5000;
                    final maxHp = (data['max_hp'] as num?)?.toInt() ?? 5000;
                    final status = (data['status'] ?? 'inconnu').toString().toUpperCase();
                    return ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _statusCard(hp, maxHp, status),
                        const SizedBox(height: 16),
                        _command('LANCER LE RAID', () => RaidAdminService.setRaidStatus(
                          'active', roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('METTRE EN ATTENTE', () => RaidAdminService.setRaidStatus(
                          'waiting', roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('RÉINITIALISER LE BOSS', () => RaidAdminService.resetBoss(
                          roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('FRAPPER LE BOSS (-250 PV)', () => RaidAdminService.strikeBoss(
                          250, roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('PROLONGER DE 5 MINUTES', () => RaidAdminService.extendRaidMinutes(
                          5, roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('RÉDUIRE DE 5 MINUTES', () => RaidAdminService.reduceRaidMinutes(
                          5, roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('RECALER À 23H00', () => RaidAdminService.resetToMidnight(
                          roomId: widget.roomId, adminKey: widget.adminKey)),
                        _command('TERMINER LE RAID', () => RaidAdminService.expireRaidNow(
                          roomId: widget.roomId, adminKey: widget.adminKey),
                          color: const Color(0xFFFF2E56)),
                        const SizedBox(height: 16),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        if (_busy) const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _statusCard(int hp, int maxHp, String status) {
    final double ratio = maxHp > 0 ? (hp / maxHp).clamp(0.0, 1.0).toDouble() : 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(color: const Color(0xFFFF9100)),
      ),
      child: Column(
        children: [
          Text(widget.roomId.toUpperCase(),
            style: const TextStyle(color: Color(0xFFFF9100), fontFamily: 'monospace')),
          const SizedBox(height: 10),
          Text('$hp / $maxHp PV',
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: ratio, minHeight: 8,
            backgroundColor: Colors.white12, color: const Color(0xFFFF2E56)),
          const SizedBox(height: 10),
          Text('ÉTAT : $status',
            style: const TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _command(String label, Future<void> Function() operation, {
    Color color = const Color(0xFFFF9100),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _busy ? null : () => _execute(label, operation),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            backgroundColor: color.withOpacity(0.06),
          ),
          child: Text(label,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
