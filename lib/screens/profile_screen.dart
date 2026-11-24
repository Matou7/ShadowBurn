import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/titles.dart';
import '../core/balance.dart';
import '../providers/game_provider.dart';
import '../providers/urgent_quest_provider.dart';
import '../widgets/system_dialog.dart';
import '../utils/admin_utils.dart';
import '../services/raid_admin_service.dart';
import '../services/lan_socket_service.dart';

const String kDefaultLanHostIp = '192.0.0.4';
const int kDefaultLanWsPort = 8765;
const int kDefaultLanWebPort = 8080;

const String kLanPackDriveFileId = '1XwHpNYysK0196tsZ-GDaumUSFmw2paJf';
const String kLanPackDownloadUrl =
    'https://drive.google.com/uc?export=download&id=$kLanPackDriveFileId';
const String kLanPackDriveViewUrl =
    'https://drive.google.com/file/d/$kLanPackDriveFileId/view?usp=sharing';
const String kLanTargetDir = '/storage/emulated/0/Download/LAN/web';

const String kTermuxAutoAllowCommand =
    'mkdir -p ~/.termux && echo "allow-external-apps = true" >> ~/.termux/termux.properties && termux-reload-settings';
const String kTermuxDepsCommand =
    'termux-setup-storage && pkg update -y && pkg install -y python && pip install websockets';
const String kTermuxManualStartCommand =
    'cd /storage/emulated/0/Download/LAN/web && chmod +x start_lan.sh && ./start_lan.sh';

class ProfileScreen extends StatefulWidget {
  final String? initialRoomId;
  final String? initialKey;

  const ProfileScreen({super.key, this.initialRoomId, this.initialKey});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _intentChannel =
      MethodChannel('com.shadowburn.app/lock');

  static const int _kAdminLeaseDurationMs = 600000;
  static const int _kAdminCommandCooldownMs = 1500;
  static const Duration _kFirestoreTimeout = Duration(seconds: 6);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _remoteConsoleKey = GlobalKey();

  String? _activeRoom;
  String? _verifiedKey;
  int _selectedHpPreset = 5000;
  bool _isCheckingIntent = false;
  bool _isBindingInProgress = false;

  bool _isLanMode = false;
  bool _isDownloadingLanPack = false;
  String _lanPackStatus = '';
  String _lanHostIp = kDefaultLanHostIp;
  String _lanWsUrl = 'ws://$kDefaultLanHostIp:$kDefaultLanWsPort';
  String _lanTvUrl = '';
  final LanSocketService _lanSocket = LanSocketService();
  StreamSubscription? _lanSub;
  int _lanCurrentHp = 5000;
  int _lanMaxHp = 5000;
  String _lanStatus = 'waiting';
  int _lanRemainingSeconds = 1800;

  final Map<String, int> _lastAdminActionMs = {};

  static String? _deviceAdminToken;
  static String? _hardwareFingerprint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeviceAdminSecurity();
    _loadSavedLanHost();

    _lanSub = _lanSocket.messages.listen((msg) {
      if (!mounted) return;
      final String msgType = (msg['type'] ?? '').toString();
      if (msgType == 'state' ||
          msgType == 'welcome' ||
          msgType == 'state_sync') {
        final Map<String, dynamic> incoming = (msg['state'] is Map)
            ? Map<String, dynamic>.from(msg['state'] as Map)
            : Map<String, dynamic>.from(msg);
        setState(() {
          _lanMaxHp = ((incoming['max_hp'] ??
                  incoming['bossMaxHp'] ??
                  _lanMaxHp) as num)
              .toInt();
          _lanCurrentHp = ((incoming['current_hp'] ??
                  incoming['bossHp'] ??
                  _lanCurrentHp) as num)
              .toInt();
          _lanStatus = (incoming['status'] ?? _lanStatus).toString();
          _lanRemainingSeconds =
              ((incoming['remaining_seconds'] ?? _lanRemainingSeconds) as num)
                  .toInt();
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final game = Provider.of<GameProvider>(context, listen: false);
      await game.ensureProStatusLoaded();
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final String? pendingLanWs = prefs.getString('shadow_lan_active_ws');
      final String? pendingLanRoom = prefs.getString('shadow_lan_active_room');
      if (pendingLanWs != null && pendingLanWs.trim().isNotEmpty) {
        await prefs.remove('shadow_lan_active_ws');
        await prefs.remove('shadow_lan_active_room');
        await _promptAndActivateLanMode(
          prefilledWsUrl: pendingLanWs.trim(),
          prefilledRoom: pendingLanRoom,
        );
        return;
      }

      if (widget.initialRoomId != null && widget.initialRoomId!.isNotEmpty) {
        await _attemptSecureBinding(
            widget.initialRoomId!, widget.initialKey ?? '');
      } else if (game.pairedAdminRoom != null &&
          game.pairedAdminRoom!.isNotEmpty) {
        await _attemptSecureBinding(
            game.pairedAdminRoom!, game.pairedAdminKey ?? '');
      } else {
        await _checkIncomingDeeplink();
      }
    });
  }

  String _generateUniqueLanRoomId() {
    final rng = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final suffix =
        List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    final shortToken = (_deviceAdminToken ?? 'DEV')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final tail = shortToken.length >= 4
        ? shortToken.substring(shortToken.length - 4)
        : shortToken.padRight(4, 'X');
    return 'LAN_${tail}_$suffix';
  }

  Future<void> _loadSavedLanHost() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedIp = prefs.getString('shadow_lan_host_ip');
    final String webHost = (kIsWeb &&
            Uri.base.host.isNotEmpty &&
            Uri.base.host != 'localhost' &&
            Uri.base.host != '127.0.0.1')
        ? Uri.base.host
        : '';
    final String resolvedIp = webHost.isNotEmpty
        ? webHost
        : ((savedIp != null && savedIp.trim().isNotEmpty)
            ? savedIp.trim()
            : kDefaultLanHostIp);

    final String autoRoom = _activeRoom ?? _generateUniqueLanRoomId();
    final String wsUrl = 'ws://$resolvedIp:$kDefaultLanWsPort';

    if (!mounted) return;
    setState(() {
      _lanHostIp = resolvedIp;
      _lanWsUrl = wsUrl;
      _lanTvUrl =
          'http://$resolvedIp:$kDefaultLanWebPort/?mode=lan&room=$autoRoom&ws=${Uri.encodeComponent(wsUrl)}';
    });
  }

  bool _isLanPackInstalledLocally() {
    if (kIsWeb) return true;
    try {
      final indexFile = File('$kLanTargetDir/index.html');
      final serverFile = File('$kLanTargetDir/server_lan.py');
      return indexFile.existsSync() && serverFile.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _launchLanServerAutomatically() async {
    if (kIsWeb) return;
    try {
      await _intentChannel.invokeMethod<bool>('runTermuxLanScript', {
        'scriptPath': '$kLanTargetDir/start_lan.sh',
      });
    } catch (e) {
      debugPrint("[LAN AUTO-START] $e");
    }
  }

  Future<void> _ensureLanPackInstalledInBackground({
    bool force = false,
    void Function(String status)? onProgress,
  }) async {
    if (kIsWeb) return;
    if (_isDownloadingLanPack) return;
    if (!force && _isLanPackInstalledLocally()) {
      const msg = "Pack LAN pret dans Download/LAN/web";
      if (mounted) {
        setState(() => _lanPackStatus = msg);
      }
      onProgress?.call(msg);
      return;
    }

    _isDownloadingLanPack = true;
    const startMsg = "Telechargement automatique du pack LAN...";
    if (mounted) {
      setState(() => _lanPackStatus = startMsg);
    }
    onProgress?.call(startMsg);

    try {
      final client = http.Client();
      try {
        http.Response response = await client
            .get(Uri.parse(kLanPackDownloadUrl))
            .timeout(const Duration(seconds: 30));

        Uint8List bytes = response.bodyBytes;

        final bool looksLikeZip =
            bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
        if (!looksLikeZip) {
          final html = utf8.decode(bytes, allowMalformed: true);
          final confirmMatch =
              RegExp(r'confirm=([0-9A-Za-z_\-]+)').firstMatch(html);
          final uuidMatch = RegExp(r'uuid=([0-9A-Za-z_\-]+)').firstMatch(html);
          if (confirmMatch != null) {
            final confirmToken = confirmMatch.group(1)!;
            final uuidPart =
                uuidMatch != null ? '&uuid=${uuidMatch.group(1)}' : '';
            final fallbackUrl =
                'https://drive.usercontent.google.com/download?id=$kLanPackDriveFileId&export=download&confirm=$confirmToken$uuidPart';
            response = await client
                .get(Uri.parse(fallbackUrl))
                .timeout(const Duration(seconds: 30));
            bytes = response.bodyBytes;
          }
        }

        if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
          throw Exception("Archive ZIP invalide recuperee depuis Drive.");
        }

        const extractMsg = "Extraction automatique vers Download/LAN/web...";
        if (mounted) {
          setState(() => _lanPackStatus = extractMsg);
        }
        onProgress?.call(extractMsg);

        final targetDir = Directory(kLanTargetDir);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final archive = ZipDecoder().decodeBytes(bytes);
        int extractedCount = 0;

        for (final file in archive) {
          String entryName = file.name.replaceAll('\\', '/');
          if (entryName.startsWith('LAN/web/')) {
            entryName = entryName.substring('LAN/web/'.length);
          } else if (entryName.startsWith('web/')) {
            entryName = entryName.substring('web/'.length);
          }
          if (entryName.isEmpty || entryName.contains('..')) continue;

          final outPath = '$kLanTargetDir/$entryName';
          if (file.isFile) {
            final outFile = File(outPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(file.content as List<int>, flush: true);
            extractedCount++;
          } else {
            await Directory(outPath).create(recursive: true);
          }
        }

        final doneMsg =
            "Pack LAN installe ($extractedCount fichiers) dans Download/LAN/web";
        if (mounted) {
          setState(() => _lanPackStatus = doneMsg);
        }
        onProgress?.call(doneMsg);
      } finally {
        client.close();
      }
    } catch (e) {
      final errMsg = "Telechargement auto en attente : $e";
      debugPrint("[LAN PACK] $errMsg");
      if (mounted) {
        setState(() => _lanPackStatus = errMsg);
      }
      onProgress?.call(errMsg);
    } finally {
      _isDownloadingLanPack = false;
    }
  }

  void _copyWithToast(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$label copie dans le presse-papiers."),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildCopyBox({
    required String value,
    required Color accentColor,
    required String toastLabel,
    bool underline = false,
  }) {
    return InkWell(
      onTap: () => _copyWithToast(value, toastLabel),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: accentColor.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: accentColor,
                fontFamily: 'monospace',
                fontSize: 9.5,
                decoration:
                    underline ? TextDecoration.underline : TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "[TOUCHER POUR COPIER]",
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptAndActivateLanMode({
    String? prefilledWsUrl,
    String? prefilledRoom,
  }) async {
    unawaited(_ensureLanPackInstalledInBackground());
    unawaited(_launchLanServerAutomatically());

    final String uniqueRoom =
        (prefilledRoom != null && prefilledRoom.trim().isNotEmpty)
            ? prefilledRoom.trim()
            : _generateUniqueLanRoomId();

    if (prefilledWsUrl != null && prefilledWsUrl.trim().isNotEmpty) {
      final Uri? parsed = Uri.tryParse(prefilledWsUrl.trim());
      final String host =
          (parsed != null && parsed.host.isNotEmpty) ? parsed.host : _lanHostIp;
      await _connectLanAdminWithHost(
        hostIp: host,
        customWsUrl: prefilledWsUrl.trim(),
        roomId: uniqueRoom,
      );
      return;
    }

    final ipController = TextEditingController(text: _lanHostIp);
    String dialogPackStatus = _lanPackStatus.isNotEmpty
        ? _lanPackStatus
        : (_isLanPackInstalledLocally()
            ? "Pack LAN pret dans Download/LAN/web"
            : "Telechargement automatique du pack LAN en cours...");

    SystemDialog.show(
      context,
      title: "SERVEUR LAN LOCAL",
      color: const Color(0xFF00FF66),
      content: StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Salle auto-attribuee : $uniqueRoom",
                  style: const TextStyle(
                    color: Color(0xFF00FF66),
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF66).withOpacity(0.07),
                    border: Border.all(
                        color: const Color(0xFF00FF66).withOpacity(0.45)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MODE AUTO (recommande)",
                        style: TextStyle(
                          color: Color(0xFF00FF66),
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "- ShadowBurn telecharge et extrait le pack dans Download/LAN/web puis lance le serveur automatiquement.\n"
                        "- A faire 1 fois dans Termux : autoriser les commandes externes puis installer stockage + Python + websockets.",
                        style: TextStyle(
                            color: Colors.white70, fontSize: 10.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Auto (1 fois dans Termux) - autoriser commandes externes :",
                  style: TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
                const SizedBox(height: 4),
                _buildCopyBox(
                  value: kTermuxAutoAllowCommand,
                  accentColor: const Color(0xFF00FF66),
                  toastLabel: "Commande autorisation Termux",
                ),
                const SizedBox(height: 8),
                const Text(
                  "Auto & Manuel (1 fois dans Termux) - stockage + Python + websockets :",
                  style: TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
                const SizedBox(height: 4),
                _buildCopyBox(
                  value: kTermuxDepsCommand,
                  accentColor: const Color(0xFF00E5FF),
                  toastLabel: "Commande prerequis Termux",
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9100).withOpacity(0.07),
                    border: Border.all(
                        color: const Color(0xFFFF9100).withOpacity(0.45)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MODE MANUEL (sans lancement auto)",
                        style: TextStyle(
                          color: Color(0xFFFF9100),
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "- Telecharge le pack via le lien Drive ci-dessous et extrais-le dans Download/LAN/web.\n"
                        "- Lance ensuite la commande de demarrage directement dans Termux.",
                        style: TextStyle(
                            color: Colors.white70, fontSize: 10.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Manuel - lien du pack LAN (Drive) :",
                  style: TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
                const SizedBox(height: 4),
                _buildCopyBox(
                  value: kLanPackDriveViewUrl,
                  accentColor: const Color(0xFF00E5FF),
                  toastLabel: "Lien Drive",
                  underline: true,
                ),
                const SizedBox(height: 8),
                const Text(
                  "Manuel - lancer le serveur dans Termux :",
                  style: TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
                const SizedBox(height: 4),
                _buildCopyBox(
                  value: kTermuxManualStartCommand,
                  accentColor: const Color(0xFFFF9100),
                  toastLabel: "Commande demarrage manuel",
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ipController,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: "IP Wi-Fi affichee par Termux (ex: 192.0.0.4)",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF00FF66))),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF00FF66))),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dialogPackStatus,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () {
                            unawaited(_ensureLanPackInstalledInBackground(
                              force: true,
                              onProgress: (status) {
                                if (dialogCtx.mounted) {
                                  setDialogState(
                                      () => dialogPackStatus = status);
                                }
                              },
                            ));
                          },
                          child: const Text(
                            "[FORCER TELECHARGEMENT AUTO PACK LAN]",
                            style: TextStyle(
                              color: Color(0xFFFF9100),
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANNULER", style: TextStyle(color: Colors.white54)),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00FF66),
            side: const BorderSide(color: Color(0xFF00FF66)),
            backgroundColor: const Color(0xFF00FF66).withOpacity(0.15),
          ),
          onPressed: () async {
            final String cleanIp = ipController.text
                .trim()
                .replaceAll('http://', '')
                .replaceAll('ws://', '')
                .split(':')
                .first;
            Navigator.pop(context);
            if (cleanIp.isNotEmpty) {
              await _connectLanAdminWithHost(
                hostIp: cleanIp,
                roomId: uniqueRoom,
              );
            }
          },
          child: const Text("CONNECTER LAN",
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _connectLanAdminWithHost({
    required String hostIp,
    String? customWsUrl,
    String? roomId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shadow_lan_host_ip', hostIp);

    final String resolvedRoom = (roomId != null && roomId.trim().isNotEmpty)
        ? roomId.trim()
        : _generateUniqueLanRoomId();
    final String wsUrl = customWsUrl ?? 'ws://$hostIp:$kDefaultLanWsPort';
    final String tvUrl =
        'http://$hostIp:$kDefaultLanWebPort/?mode=lan&room=$resolvedRoom&ws=${Uri.encodeComponent(wsUrl)}';

    await Clipboard.setData(ClipboardData(text: tvUrl));

    RaidAdminService.configureLan(wsUrl: wsUrl, roomId: resolvedRoom);

    final bool connected = await _lanSocket.connect(wsUrl);
    if (connected) {
      _lanSocket.sendJson({
        'type': 'join',
        'role': 'admin',
        'room': resolvedRoom,
        'roomId': resolvedRoom,
        'hunterId': _deviceAdminToken ?? 'admin_lan',
        'name': 'Admin_LAN',
      });
    }

    if (!mounted) return;
    setState(() {
      _isLanMode = true;
      _lanHostIp = hostIp;
      _lanWsUrl = wsUrl;
      _activeRoom = resolvedRoom;
      _verifiedKey = 'LAN';
      _lanTvUrl = tvUrl;
      _lanMaxHp = 5000;
      _lanCurrentHp = 5000;
      _lanStatus = 'waiting';
      _lanRemainingSeconds = 1800;
    });

    _scrollToRemoteConsole();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(connected
            ? "LAN [$resolvedRoom] connecte ($wsUrl). Lien TV copie."
            : "Mode LAN [$resolvedRoom] pret (WS non joint sur $wsUrl). Lien TV copie."),
        backgroundColor:
            connected ? const Color(0xFF00FF66) : const Color(0xFFFF9100),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatLanClock(int seconds) {
    final int m = (seconds ~/ 60).clamp(0, 999);
    final int s = (seconds % 60).clamp(0, 59);
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  Future<void> _initDeviceAdminSecurity() async {
    final prefs = await SharedPreferences.getInstance();

    String? token = prefs.getString('shadow_device_admin_token');
    if (token == null || token.isEmpty) {
      token =
          'admin_inst_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await prefs.setString('shadow_device_admin_token', token);
    }
    _deviceAdminToken = token;

    String? hw = prefs.getString('shadow_hardware_fingerprint');
    if (hw == null || hw.isEmpty) {
      hw =
          'hw_sig_${PlatformDispatcher.instance.views.first.physicalSize.width.toInt()}_${Random().nextInt(99999999)}';
      await prefs.setString('shadow_hardware_fingerprint', hw);
    }
    _hardwareFingerprint = hw;
  }

  Future<void> _releaseAdminLease(String? roomId) async {
    if (roomId == null || roomId.isEmpty || _deviceAdminToken == null) return;
    try {
      final docRef =
          FirebaseFirestore.instance.collection('current_raids').doc(roomId);
      final doc = await docRef.get().timeout(_kFirestoreTimeout);
      if (!doc.exists) return;
      final data = Map<String, dynamic>.from(doc.data() as Map? ?? {});
      if (data['admin_instance_token']?.toString() == _deviceAdminToken) {
        await docRef.update({
          'admin_instance_token': FieldValue.delete(),
          'admin_last_seen_ms': FieldValue.delete(),
          'lease_expires_at': FieldValue.delete(),
        }).timeout(_kFirestoreTimeout);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLanMode) {
      _checkIncomingDeeplink();
    }
  }

  void _scrollToRemoteConsole() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _remoteConsoleKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkIncomingDeeplink() async {
    if (_isCheckingIntent || _isBindingInProgress) return;
    _isCheckingIntent = true;

    try {
      String? rawUrl;

      if (!kIsWeb) {
        try {
          rawUrl = await _intentChannel
              .invokeMethod<String>('getInitialIntentUrl')
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      if (rawUrl == null || rawUrl.isEmpty) {
        rawUrl = Uri.base.toString();
      }

      if (rawUrl.contains('mode=lan') || rawUrl.contains('ws=')) {
        try {
          final parsedUri = Uri.parse(rawUrl);
          String? wsParam = parsedUri.queryParameters['ws'];
          String? roomId = parsedUri.queryParameters['room'];
          if (wsParam == null && parsedUri.fragment.contains('?')) {
            final fragParams =
                Uri.splitQueryString(parsedUri.fragment.split('?').last);
            wsParam = fragParams['ws'];
            roomId = fragParams['room'] ?? roomId;
          }
          if (wsParam != null && wsParam.isNotEmpty) {
            await _promptAndActivateLanMode(
              prefilledWsUrl: Uri.decodeComponent(wsParam),
              prefilledRoom: roomId,
            );
            return;
          }
        } catch (e) {
          debugPrint("Erreur deeplink LAN: $e");
        }
      }

      if (rawUrl.contains('room=')) {
        try {
          final parsedUri = Uri.parse(rawUrl);
          String? roomId = parsedUri.queryParameters['room'];
          String? key = parsedUri.queryParameters['key'];

          if (roomId == null && parsedUri.fragment.contains('?')) {
            final fragParams =
                Uri.splitQueryString(parsedUri.fragment.split('?').last);
            roomId = fragParams['room'];
            key = fragParams['key'];
          }

          if (roomId != null && roomId.isNotEmpty) {
            await _attemptSecureBinding(roomId, key ?? '');
          }
        } catch (e) {
          debugPrint("Erreur analyse deeplink: $e");
        }
      }
    } finally {
      _isCheckingIntent = false;
    }
  }

  void _rejectIntrusionAttempt(String reason) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason),
        backgroundColor: const Color(0xFFFF2E56),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _attemptSecureBinding(String roomId, String secretKey) async {
    if (!mounted || _isBindingInProgress) return;
    _isBindingInProgress = true;

    try {
      final cleanRoomId = roomId.trim();
      final cleanKey = secretKey.trim();

      if (cleanRoomId.isEmpty) return;

      if (cleanRoomId.toUpperCase().startsWith('LAN_') ||
          cleanKey.toUpperCase() == 'LAN') {
        await _connectLanAdminWithHost(
          hostIp: _lanHostIp,
          roomId: cleanRoomId,
        );
        return;
      }

      if (_deviceAdminToken == null || _hardwareFingerprint == null) {
        await _initDeviceAdminSecurity();
      }

      final game = Provider.of<GameProvider>(context, listen: false);
      final bool isProVerified = await game.ensureProStatusLoaded();
      if (!mounted) return;

      if (!isProVerified) {
        _rejectIntrusionAttempt("ACCES REFUSE : STATUT MONARQUE PRO REQUIS.");
        return;
      }

      final docRef = FirebaseFirestore.instance
          .collection('current_raids')
          .doc(cleanRoomId);
      final doc = await docRef.get().timeout(_kFirestoreTimeout);

      if (!doc.exists) {
        _unbindFromRoom("Donjon [$cleanRoomId] inexistant ou ferme.");
        return;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(doc.data() as Map? ?? {});
      final String expectedKey = (data['admin_key'] ?? '').toString().trim();

      if (expectedKey.isNotEmpty &&
          cleanKey.isNotEmpty &&
          expectedKey != cleanKey) {
        _rejectIntrusionAttempt("ACCES REFUSE : Cle Maitre invalide.");
        return;
      }

      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final String? existingAdminInstance =
          data['admin_instance_token']?.toString();
      final int lastAdminSeenMs =
          (data['admin_last_seen_ms'] as num?)?.toInt() ?? 0;
      final int leaseExpiresAtMs = (data['lease_expires_at'] as num?)?.toInt() ??
          (lastAdminSeenMs > 0
              ? lastAdminSeenMs + _kAdminLeaseDurationMs
              : 0);

      final bool leaseStillValid = leaseExpiresAtMs > nowMs ||
          (lastAdminSeenMs > 0 &&
              (nowMs - lastAdminSeenMs) < _kAdminLeaseDurationMs);

      final bool occupiedByOtherInstance = existingAdminInstance != null &&
          existingAdminInstance.isNotEmpty &&
          existingAdminInstance != _deviceAdminToken &&
          leaseStillValid;

      if (occupiedByOtherInstance) {
        if (_activeRoom != cleanRoomId) {
          await game.unpairAdminRoom();
        }
        _rejectIntrusionAttempt(
            "INTRUSION REFUSEE : Un autre administrateur controle deja [$cleanRoomId].");
        return;
      }

      await docRef.set({
        'admin_instance_token': _deviceAdminToken,
        'hardware_fingerprint': _hardwareFingerprint,
        'admin_last_seen_ms': nowMs,
        'lease_expires_at': nowMs + _kAdminLeaseDurationMs,
        'last_activity_ms': nowMs,
      }, SetOptions(merge: true)).timeout(_kFirestoreTimeout);

      await game.pairAdminRoom(cleanRoomId, adminKey: cleanKey);

      final int rawMaxHp = ((data['max_hp'] ?? 5000) as num).toInt();
      final bool presetExists =
          RaidAdminService.raidPresets.any((p) => p['hp'] == rawMaxHp);

      if (!mounted) return;
      RaidAdminService.clearLan();
      await _lanSocket.disconnect();
      setState(() {
        _isLanMode = false;
        _activeRoom = cleanRoomId;
        _verifiedKey = cleanKey;
        _selectedHpPreset = presetExists ? rawMaxHp : 5000;
      });

      _scrollToRemoteConsole();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Telecommande Maitre active sur [$cleanRoomId]"),
            backgroundColor: const Color(0xFF00FF66),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Delai reseau depasse lors de la liaison au portail."),
            backgroundColor: Color(0xFFFF2E56),
          ),
        );
      }
    } catch (e) {
      _rejectIntrusionAttempt("Erreur de connexion : $e");
    } finally {
      _isBindingInProgress = false;
    }
  }

  Future<void> _runGuardedAdminCommand({
    required String actionKey,
    required String successLabel,
    required Map<String, dynamic> lanPayload,
    required void Function() lanOptimisticUpdate,
    required Future<String?> Function() remoteCommand,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int prev = _lastAdminActionMs[actionKey] ?? 0;
    if (now - prev < _kAdminCommandCooldownMs) {
      final int remSec =
          ((_kAdminCommandCooldownMs - (now - prev)) / 1000).ceil();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Anti-spam actif : patientez ${remSec}s."),
            backgroundColor: const Color(0xFFFF9100),
            duration: const Duration(milliseconds: 900),
          ),
        );
      }
      return;
    }

    _lastAdminActionMs[actionKey] = now;

    if (_isLanMode) {
      lanOptimisticUpdate();
      final String room = _activeRoom ?? _generateUniqueLanRoomId();
      _lanSocket.sendJson({
        'room': room,
        'roomId': room,
        'role': 'admin',
        'actorId': _deviceAdminToken ?? 'admin_lan',
        ...lanPayload,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successLabel),
            backgroundColor: const Color(0xFF00FF66),
            duration: const Duration(milliseconds: 900),
          ),
        );
      }
      return;
    }

    final String? error = await remoteCommand();
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFFF2E56),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successLabel),
          backgroundColor: const Color(0xFF00FF66),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  void _confirmDestructiveAdminAction({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirmed,
  }) {
    SystemDialog.show(
      context,
      title: title,
      color: const Color(0xFFFF2E56),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANNULER", style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF2E56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () {
            Navigator.pop(context);
            onConfirmed();
          },
          child: Text(
            confirmLabel,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  void _unbindFromRoom(String reason) {
    final wasLan = _isLanMode;
    final roomToRelease = _activeRoom;
    if (!wasLan && roomToRelease != null) {
      _releaseAdminLease(roomToRelease);
    }
    if (wasLan) {
      RaidAdminService.clearLan();
      _lanSocket.disconnect();
    }
    if (!mounted) return;
    Provider.of<GameProvider>(context, listen: false).unpairAdminRoom();
    setState(() {
      _isLanMode = false;
      _activeRoom = null;
      _verifiedKey = null;
      _lanStatus = 'waiting';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason),
        backgroundColor: const Color(0xFFFF2E56),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lanSub?.cancel();
    _lanSocket.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatStat(int value) {
    if (value >= 1000000) return "${(value / 1000000).toStringAsFixed(1)}M";
    if (value >= 1000) return "${(value / 1000).toStringAsFixed(1)}K";
    return value.toString();
  }

  String _formatDate(String isoDate) {
    DateTime dt = DateTime.parse(isoDate);
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _showProKeyDialog(BuildContext context, GameProvider game) {
    final keyController = TextEditingController();

    SystemDialog.show(
      context,
      title: "ACTIVER STATUT MONARQUE",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Entrez votre cle de licence Pro ou verifiez votre achat instantanement via l'empreinte de votre appareil :",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: keyController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Cle de licence Pro (ex: SHADOW-...)",
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF9100))),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF9100))),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Color(0xFF00E5FF)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              icon: const Icon(Icons.security, size: 16),
              label: const Text(
                "VERIFIER MON APPAREIL (AUTOMATIQUE)",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);

                messenger.showSnackBar(
                  const SnackBar(
                      content:
                          Text("Interrogation de l'empreinte materielle...")),
                );

                final bool success = await game.requestHardwareAutoRecovery();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? "Pass Pro restaure et active avec succes !"
                        : "Aucun achat detecte pour cet appareil."),
                    backgroundColor: success ? Colors.green : Colors.redAccent,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      color: const Color(0xFFFF9100),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ANNULER")),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF9100)),
            backgroundColor: const Color(0xFFFF9100).withOpacity(0.2),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final keyInput = keyController.text.trim();
            Navigator.pop(context);

            if (keyInput.isNotEmpty) {
              final bool success = await game.activateProKey(keyInput);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(success
                      ? "Statut Monarque active avec succes !"
                      : "Cle invalide ou deja liee a un autre materiel."),
                  backgroundColor: success ? Colors.green : Colors.redAccent,
                ),
              );
            }
          },
          child: const Text("VALIDER LA CLE",
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  void _showSupportDialog(BuildContext context) {
    final emailController = TextEditingController();
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    SystemDialog.show(
      context,
      title: "CANAL DE SUPPORT",
      color: const Color(0xFF00E5FF),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Une anomalie dans le Systeme ou une question sur vos quetes ? Entrez votre e-mail et votre message.",
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "E-mail de contact (ex: hunter@domain.com)",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00E5FF))),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00E5FF))),
                errorStyle: TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "L'e-mail est requis.";
                }
                if (!emailRegex.hasMatch(value.trim())) {
                  return "Format invalide (ex: nom@domaine.fr/.com)";
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: messageController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Votre message...",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00E5FF))),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00E5FF))),
                errorStyle: TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Le message ne peut pas etre vide.";
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANNULER", style: TextStyle(color: Colors.white38)),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF00E5FF)),
            backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () async {
            if (formKey.currentState!.validate()) {
              final email = emailController.text.trim();
              final message = messageController.text.trim();

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("Transmission du rapport au Systeme en cours..."),
                    duration: Duration(seconds: 2)),
              );

              try {
                final response = await http
                    .post(
                      Uri.parse(
                          'https://shadowburn-webhook.onrender.com/api/contact'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'email': email, 'message': message}),
                    )
                    .timeout(const Duration(seconds: 10));

                if (response.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "Rapport transmis avec succes ! Le Quartier General a recu votre message."),
                      backgroundColor: Color(0xFF00FF66),
                    ),
                  );
                } else {
                  final errorData = jsonDecode(response.body);
                  final errorMsg = errorData['detail'] ??
                      "Echec de la transmission du rapport.";
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(errorMsg),
                        backgroundColor: Colors.redAccent),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text("Erreur de connexion au serveur : $e"),
                      backgroundColor: Colors.redAccent),
                );
              }
            }
          },
          child: const Text("ENVOYER", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    const Color systemBlue = Color(0xFF00E5FF);
    final Color borderBlue = systemBlue.withOpacity(0.5);
    final Color rankColor = game.isGodMode ? Colors.redAccent : Colors.white;

    if (!_isLanMode &&
        game.isPro &&
        game.pairedAdminRoom != null &&
        game.pairedAdminRoom!.isNotEmpty &&
        _activeRoom != game.pairedAdminRoom &&
        !_isBindingInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_isLanMode &&
            _activeRoom != game.pairedAdminRoom &&
            !_isBindingInProgress) {
          _attemptSecureBinding(
              game.pairedAdminRoom!, game.pairedAdminKey ?? '');
        }
      });
    }

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
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: borderBlue, width: 2),
                    color: Colors.black.withOpacity(0.7),
                    boxShadow: [
                      BoxShadow(
                          color: systemBlue.withOpacity(0.15), blurRadius: 20)
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildSectionHeader("STATUT", systemBlue),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                        child: Column(
                          children: [
                            GestureDetector(
                              onLongPress: () =>
                                  _showEditUsernameDialog(context, game),
                              child: Text(
                                game.username.toUpperCase(),
                                style: GoogleFonts.orbitron(
                                  color: systemBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                  shadows: [
                                    Shadow(
                                        color: systemBlue.withOpacity(0.5),
                                        blurRadius: 10)
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                GestureDetector(
                                  onLongPress: () {
                                    if (!kDebugMode &&
                                        game.rank.toUpperCase() != "MONARQUE") {
                                      return;
                                    }

                                    if (game.isGodMode) {
                                      showExitGodModeDialog(context, game);
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
                                            const Shadow(
                                                color: systemBlue,
                                                blurRadius: 10),
                                            Shadow(
                                                color:
                                                    systemBlue.withOpacity(0.8),
                                                blurRadius: 30),
                                            if (game.isGodMode)
                                              const Shadow(
                                                  color: Colors.red,
                                                  blurRadius: 50),
                                          ])),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text("RANG",
                                      style: GoogleFonts.orbitron(
                                          color: systemBlue,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            if (game.isGodMode)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Text("[ GOD MODE ACTIF : BAC A SABLE ]",
                                    style: GoogleFonts.orbitron(
                                        color: Colors.redAccent,
                                        fontSize: 10,
                                        letterSpacing: 2)),
                              ),
                            GestureDetector(
                              onTap: () => _showTitlesDialog(context, game),
                              child: Text(
                                  "TITRE: ${game.equippedTitle.toUpperCase()}",
                                  style: GoogleFonts.rajdhani(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "PREMIER EVEIL : ${game.awakeningDate}",
                              style: GoogleFonts.orbitron(
                                color: Colors.white38,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
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
                            _buildStatusLine("PV", game.currentHealth,
                                game.maxHealth, systemBlue, context,
                                isEditable: true, game: game, stat: "HP"),
                            const SizedBox(height: 15),
                            _buildStatusLine(
                                "XP",
                                game.currentXP.toInt(),
                                game.nextRankThreshold.toInt(),
                                const Color(0xFFD500F9),
                                context,
                                isEditable: true,
                                game: game,
                                stat: "XP"),
                            const SizedBox(height: 10),
                            _buildSurpassement(
                                context, game, game.totalSurpassement),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      _buildAttributesGrid(context, game),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Text("HISTORIQUE DE DEVELOPPEMENT",
                    style: GoogleFonts.orbitron(
                        color: systemBlue,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildHeatMap(game, context),
                const SizedBox(height: 35),
                if (game.saveHistory.isNotEmpty) ...[
                  _buildArchiveList(context, game, systemBlue),
                ],
                const SizedBox(height: 35),
                Container(
                  key: _remoteConsoleKey,
                  child: _buildRaidRemoteConsole(context, game, systemBlue),
                ),
                const SizedBox(height: 35),
                if (game.isGodMode) ...[
                  _buildTestSection(context, game, systemBlue),
                  const SizedBox(height: 15),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: Colors.redAccent.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.red.withOpacity(0.05),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "PERSISTANCE PENALITE",
                          style: GoogleFonts.orbitron(
                              color: Colors.redAccent, fontSize: 11),
                        ),
                        Switch(
                          value: game.godModePersistPenalty,
                          activeColor: Colors.redAccent,
                          onChanged: (val) {
                            game.toggleGodModePersistPenalty();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                ],
                SizedBox(
                  width: double.infinity,
                  child: _holoButton(
                    "CANAL DE SUPPORT (CONTACT)",
                    systemBlue,
                    () => _showSupportDialog(context),
                    icon: Icons.support_agent,
                  ),
                ),
                const SizedBox(height: 15),
                _buildSystemButtons(context, game, systemBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRaidRemoteConsole(
      BuildContext context, GameProvider game, Color systemBlue) {
    final String? effectiveRoom =
        _isLanMode ? _activeRoom : (_activeRoom ?? game.pairedAdminRoom);
    final bool hasActiveLink =
        effectiveRoom != null && effectiveRoom.trim().isNotEmpty;

    if (!game.isPro && !hasActiveLink && !_isLanMode) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF04101E),
          border: Border.all(color: Colors.white12, width: 1.0),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, color: Color(0xFFFF9100), size: 18),
                SizedBox(width: 8),
                Text(
                  "TELECOMMANDE MAITRE (ADMIN)",
                  style: TextStyle(
                    color: Colors.white54,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Reserve exclusivement aux detenteurs de la cle Monarque Pro.\nEn mode gratuit, rejoignez les raids comme invite via le scan Chasseur.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF9100),
                side: const BorderSide(color: Color(0xFFFF9100)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              icon: const Icon(Icons.vpn_key, size: 16),
              label: const Text("ACTIVER / RESTAURER LE STATUT PRO",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => _showProKeyDialog(context, game),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF04101E),
        border: Border.all(
          color: hasActiveLink ? const Color(0xFFFF9100) : Colors.white12,
          width: hasActiveLink ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    hasActiveLink ? Icons.security : Icons.lock_outline,
                    color:
                        hasActiveLink ? const Color(0xFFFF9100) : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "TELECOMMANDE MAITRE",
                    style: GoogleFonts.orbitron(
                      color: hasActiveLink
                          ? const Color(0xFFFF9100)
                          : Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasActiveLink
                      ? const Color(0xFFFF9100).withOpacity(0.15)
                      : Colors.white10,
                  border: Border.all(
                    color: hasActiveLink
                        ? const Color(0xFFFF9100)
                        : Colors.white24,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hasActiveLink ? effectiveRoom!.toUpperCase() : "NON JUMELE",
                  style: GoogleFonts.orbitron(
                    color: hasActiveLink
                        ? const Color(0xFFFF9100)
                        : Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasActiveLink) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
              child: Column(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: const Text(
                      "Choisissez LAN (salle auto-isolee Wi-Fi local) ou MULTI (scan QR Code & Firestore).",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00FF66),
                            backgroundColor:
                                const Color(0xFF00FF66).withOpacity(0.08),
                            side: const BorderSide(
                                color: Color(0xFF00FF66), width: 1.2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          icon: const Icon(Icons.wifi_tethering, size: 15),
                          label: Text(
                            "LAN",
                            style: GoogleFonts.orbitron(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          onPressed: () => _promptAndActivateLanMode(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF9100),
                            backgroundColor:
                                const Color(0xFFFF9100).withOpacity(0.08),
                            side: const BorderSide(
                                color: Color(0xFFFF9100), width: 1.2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          icon: const Icon(Icons.qr_code_scanner, size: 15),
                          label: Text(
                            "MULTI",
                            style: GoogleFonts.orbitron(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          onPressed: _checkIncomingDeeplink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            if (_isLanMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF66).withOpacity(0.08),
                  border: Border.all(color: const Color(0xFF00FF66)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Text(
                      "LAN WS • ${_lanSocket.isConnected ? 'CONNECTE' : 'HORS-LIGNE'} • STATUT: ${_lanStatus.toUpperCase()} • BOSS: $_lanCurrentHp / $_lanMaxHp PV • ${_formatLanClock(_lanRemainingSeconds)}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF00FF66),
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _lanTvUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("URL TV LAN copiee !"),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Text(
                        "Lien Chasseurs / TV : $_lanTvUrl\n(Toucher pour copier le lien)",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontSize: 9,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _promptAndActivateLanMode(),
                      child: const Text(
                        "NOUVELLE SALLE LAN / IP",
                        style: TextStyle(
                          color: Color(0xFFFF9100),
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "CONFIGURATION DU BOSS :",
                style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.black45,
                border:
                    Border.all(color: const Color(0xFFFF9100).withOpacity(0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedHpPreset,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF04101E),
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 11),
                  items: RaidAdminService.raidPresets.map((preset) {
                    final int hp = preset['hp'] as int;
                    final String label = preset['label'] as String;
                    return DropdownMenuItem<int>(
                      value: hp,
                      child: Text(
                        label,
                        style: const TextStyle(color: Color(0xFFFF9100)),
                      ),
                    );
                  }).toList(),
                  onChanged: (int? newHp) async {
                    if (newHp != null) {
                      final selected = RaidAdminService.raidPresets
                          .firstWhere((p) => p['hp'] == newHp);
                      await _runGuardedAdminCommand(
                        actionKey: 'preset',
                        successLabel: "Boss configure : ${selected['label']}",
                        lanPayload: {
                          'type': 'admin',
                          'command': 'set_preset',
                          'maxHp': newHp,
                          'label': selected['label'].toString(),
                        },
                        lanOptimisticUpdate: () {
                          setState(() {
                            _selectedHpPreset = newHp;
                            _lanMaxHp = newHp;
                            _lanCurrentHp = newHp;
                          });
                        },
                        remoteCommand: () => RaidAdminService.applyPreset(
                          newHp,
                          selected['label'] as String,
                          roomId: effectiveRoom,
                        ),
                      );
                      if (mounted) {
                        setState(() => _selectedHpPreset = newHp);
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "AJUSTER LE CHRONO :",
                style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _compactButton("+1 MIN", const Color(0xFF00E5FF), () {
                    _runGuardedAdminCommand(
                      actionKey: 'extend_time',
                      successLabel: "+1 minute ajoutee.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'add_minutes',
                        'minutes': 1,
                      },
                      lanOptimisticUpdate: () =>
                          setState(() => _lanRemainingSeconds += 60),
                      remoteCommand: () => RaidAdminService.extendRaidMinutes(1,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _compactButton("+15 MIN", systemBlue, () {
                    _runGuardedAdminCommand(
                      actionKey: 'extend_time',
                      successLabel: "+15 minutes ajoutees.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'add_minutes',
                        'minutes': 15,
                      },
                      lanOptimisticUpdate: () =>
                          setState(() => _lanRemainingSeconds += 900),
                      remoteCommand: () => RaidAdminService.extendRaidMinutes(15,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _compactButton("+30 MIN", systemBlue, () {
                    _runGuardedAdminCommand(
                      actionKey: 'extend_time',
                      successLabel: "+30 minutes ajoutees.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'add_minutes',
                        'minutes': 30,
                      },
                      lanOptimisticUpdate: () =>
                          setState(() => _lanRemainingSeconds += 1800),
                      remoteCommand: () => RaidAdminService.extendRaidMinutes(30,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _compactButton("-1 MIN", const Color(0xFFFFAB91), () {
                    _runGuardedAdminCommand(
                      actionKey: 'reduce_time',
                      successLabel: "-1 minute retiree.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'add_minutes',
                        'minutes': -1,
                      },
                      lanOptimisticUpdate: () => setState(() =>
                          _lanRemainingSeconds =
                              (_lanRemainingSeconds - 60).clamp(0, 999999)),
                      remoteCommand: () => RaidAdminService.reduceRaidMinutes(1,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _compactButton("-15 MIN", const Color(0xFFFF7043), () {
                    _runGuardedAdminCommand(
                      actionKey: 'reduce_time',
                      successLabel: "-15 minutes retirees.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'add_minutes',
                        'minutes': -15,
                      },
                      lanOptimisticUpdate: () => setState(() =>
                          _lanRemainingSeconds =
                              (_lanRemainingSeconds - 900).clamp(0, 999999)),
                      remoteCommand: () => RaidAdminService.reduceRaidMinutes(15,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _compactButton("-30 MIN", const Color(0xFFFF7043), () {
                    _runGuardedAdminCommand(
                      actionKey: 'reduce_time',
                      successLabel: "-30 minutes retirees.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'add_minutes',
                        'minutes': -30,
                      },
                      lanOptimisticUpdate: () => setState(() =>
                          _lanRemainingSeconds =
                              (_lanRemainingSeconds - 1800).clamp(0, 999999)),
                      remoteCommand: () => RaidAdminService.reduceRaidMinutes(30,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: _compactButton("RESET A 0", const Color(0xFFFF2E56), () {
                _confirmDestructiveAdminAction(
                  title: "CONFIRMER RESET A 0",
                  message:
                      "Mettre fin immediatement au chronometre de [$effectiveRoom] ?",
                  confirmLabel: "CLOTURER MAINTENANT",
                  onConfirmed: () {
                    _runGuardedAdminCommand(
                      actionKey: 'expire_now',
                      successLabel: "Raid cloture (chrono a 0).",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'expire_now',
                      },
                      lanOptimisticUpdate: () => setState(() {
                        _lanRemainingSeconds = 0;
                        _lanStatus = 'failed';
                      }),
                      remoteCommand: () =>
                          RaidAdminService.expireRaidNow(roomId: effectiveRoom),
                    );
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "COMMANDES DU BOSS :",
                style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _compactButton("LANCER", const Color(0xFF00FF66), () {
                    _runGuardedAdminCommand(
                      actionKey: 'launch_raid',
                      successLabel: "Raid lance sur [$effectiveRoom] !",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'start',
                      },
                      lanOptimisticUpdate: () =>
                          setState(() => _lanStatus = 'active'),
                      remoteCommand: () => RaidAdminService.setRaidStatus(
                          'active',
                          roomId: effectiveRoom),
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _compactButton("-200 PV", const Color(0xFFFF9100), () {
                    _runGuardedAdminCommand(
                      actionKey: 'strike_boss',
                      successLabel: "-200 PV infliges au Boss.",
                      lanPayload: {
                        'type': 'admin',
                        'command': 'strike_boss',
                        'damage': 200,
                      },
                      lanOptimisticUpdate: () => setState(() {
                        _lanCurrentHp =
                            (_lanCurrentHp - 200).clamp(0, _lanMaxHp);
                        if (_lanCurrentHp <= 0) {
                          _lanStatus = 'victory';
                        }
                      }),
                      remoteCommand: () => RaidAdminService.strikeBoss(200,
                          roomId: effectiveRoom),
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _compactButton("RESET BOSS", const Color(0xFFFF2E56), () {
                    _confirmDestructiveAdminAction(
                      title: "CONFIRMER RESET BOSS",
                      message:
                          "Remettre les PV du Boss au maximum et les scores a zero sur [$effectiveRoom] ?",
                      confirmLabel: "REINITIALISER",
                      onConfirmed: () {
                        _runGuardedAdminCommand(
                          actionKey: 'reset_boss',
                          successLabel: "Boss et scores reinitialises.",
                          lanPayload: {
                            'type': 'admin',
                            'command': 'reset_boss',
                          },
                          lanOptimisticUpdate: () => setState(() {
                            _lanCurrentHp = _lanMaxHp;
                            _lanStatus = 'active';
                          }),
                          remoteCommand: () =>
                              RaidAdminService.resetBoss(roomId: effectiveRoom),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _unbindFromRoom("Deconnexion volontaire."),
                icon:
                    const Icon(Icons.link_off, color: Colors.white38, size: 14),
                label: const Text(
                  "DECONNECTER",
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactButton(String text, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 38,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: color.withOpacity(0.6), width: 1.2),
          backgroundColor: color.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onTap,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showTitlesDialog(BuildContext context, GameProvider game) {
    const Color systemBlue = Color(0xFF00E5FF);

    final stats = TitleStats(
      rankIndex: Balance.order.indexOf(game.rank),
      streak: game.currentStreak,
      pompes: game.totalPompes,
      abdos: game.totalAbdos,
      squats: game.totalSquats,
      km: game.totalKm,
      dungeons: game.dungeonsCompleted,
      surpass: game.totalSurpassement,
    );

    SystemDialog.show(
      context,
      title: "PANTHEON DES TITRES",
      color: systemBlue,
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(
          children: Titles.catalog.map((t) {
            final bool unlocked = t.isUnlocked(stats);

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: unlocked
                    ? systemBlue.withOpacity(0.08)
                    : Colors.white.withOpacity(0.02),
                border: Border.all(
                  color: unlocked
                      ? systemBlue.withOpacity(0.4)
                      : Colors.white10,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(
                  unlocked ? Icons.verified : Icons.lock_outline,
                  color: unlocked ? systemBlue : Colors.white24,
                  size: 22,
                ),
                title: Text(
                  t.name.toUpperCase(),
                  style: GoogleFonts.orbitron(
                    color: unlocked ? Colors.white : Colors.white30,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
                subtitle: Text(
                  t.requirement,
                  style: GoogleFonts.rajdhani(
                    color: unlocked ? systemBlue : Colors.white38,
                    fontSize: 12,
                  ),
                ),
                trailing: Text(
                  unlocked ? "ACCOMPLI" : "VERROUILLE",
                  style: GoogleFonts.orbitron(
                    color: unlocked ? systemBlue : Colors.white24,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("FERMER"),
        ),
      ],
    );
  }

  Widget _buildTestSection(
      BuildContext context, GameProvider game, Color color) {
    return Column(
      children: [
        Text("LABORATOIRE DE TEST (5S)",
            style: GoogleFonts.orbitron(
                color: Colors.redAccent, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _holoButton(
                "TEST DONJON",
                Colors.redAccent,
                () {
                  game.testDungeonWithDelay();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Apparition d'un Portail (10s) dans 5s... Allez voir vos cles.")),
                  );
                },
                icon: Icons.door_sliding_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _holoButton(
            "TEST QUETE URGENTE",
            Colors.purpleAccent,
            () {
              try {
                final urgentProv =
                    Provider.of<UrgentQuestProvider>(context, listen: false);
                urgentProv.spawnTestUrgentQuest();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text("Alerte ! Une Quete Urgente vient de se declencher."),
                    backgroundColor: Colors.purpleAccent,
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text("Erreur declenchement quete urgente : $e"),
                      backgroundColor: Colors.red),
                );
              }
            },
            icon: Icons.bolt,
          ),
        ),
      ],
    );
  }

  void _showEditUsernameDialog(BuildContext context, GameProvider game) {
    final controller = TextEditingController(text: game.username);
    SystemDialog.show(
      context,
      title: "IDENTITE",
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
            hintText: "Nouveau pseudo",
            hintStyle: TextStyle(color: Colors.white24)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ANNULER")),
        TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                game.updateUsername(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text("VALIDER")),
      ],
    );
  }

  Widget _buildGoldBadge(GameProvider game, BuildContext context) {
    return GestureDetector(
      onTap: () => _showShopDialog(context, game),
      onLongPress:
          game.isGodMode ? () => _showEditStatDialog(context, game, "OR") : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFFD700)),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFFFD700).withOpacity(0.05)),
        child: Text("OR: ${game.goldCoins}",
            style: GoogleFonts.orbitron(
                color: const Color(0xFFFFD700),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
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
          _buildEditableAttribute(
              context, game, "POMPES", _formatStat(game.totalPompes)),
          _buildEditableAttribute(
              context, game, "ABDOS", _formatStat(game.totalAbdos)),
          _buildEditableAttribute(
              context, game, "SQUATS", _formatStat(game.totalSquats)),
          _buildEditableAttribute(
              context, game, "ENDURANCE", "${game.totalKm.toStringAsFixed(1)} KM"),
          _buildEditableAttribute(
              context, game, "DISCIPLINE", game.currentStreak.toString()),
        ],
      ),
    );
  }

  Widget _buildEditableAttribute(
      BuildContext context, GameProvider game, String label, String value) {
    return GestureDetector(
      onLongPress:
          game.isGodMode ? () => _showEditStatDialog(context, game, label) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_box_outlined,
              color: game.isGodMode ? Colors.redAccent : const Color(0xFF00E5FF),
              size: 14),
          const SizedBox(width: 5),
          Text("$label: ",
              style: GoogleFonts.orbitron(
                  color: const Color(0xFF00E5FF), fontSize: 11)),
          Text(value,
              style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showEditStatDialog(
      BuildContext context, GameProvider game, String label) {
    String initialText = "0";
    final upper = label.toUpperCase();
    if (upper == "OR") {
      initialText = game.goldCoins.toString();
    } else if (upper.contains("SURPASS")) {
      initialText = game.totalSurpassement.toString();
    } else if (upper == "POMPES") {
      initialText = game.totalPompes.toString();
    } else if (upper == "ABDOS") {
      initialText = game.totalAbdos.toString();
    } else if (upper == "SQUATS") {
      initialText = game.totalSquats.toString();
    } else if (upper == "ENDURANCE") {
      initialText = game.totalKm.toStringAsFixed(1);
    } else if (upper == "DISCIPLINE") {
      initialText = game.currentStreak.toString();
    } else if (upper == "XP") {
      initialText = game.currentXP.toInt().toString();
    } else if (upper == "HP" || upper == "PV") {
      initialText = game.currentHealth.toString();
    }

    final controller = TextEditingController(text: initialText);
    SystemDialog.show(
      context,
      title: "MODIFIER $label",
      color: game.isGodMode ? Colors.redAccent : const Color(0xFF00E5FF),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
            hintText: "Nouvelle valeur",
            hintStyle: TextStyle(color: Colors.white24)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ANNULER")),
        TextButton(
            onPressed: () {
              if (label == "OR") {
                int? val = int.tryParse(controller.text);
                if (val != null) {
                  game.setGoldCoins(val);
                }
              } else if (label.toLowerCase().contains("surpass")) {
                int? val = int.tryParse(controller.text);
                if (val != null) {
                  game.setTotalSurpass(val);
                }
              } else if (label == "XP") {
                double? val = double.tryParse(controller.text);
                if (val != null) {
                  game.adminAddXp(val - game.currentXP);
                }
              } else if (label == "HP") {
                game.adminHeal();
              } else {
                double? val = double.tryParse(controller.text);
                if (val != null) {
                  game.updateTotalStat(label, val);
                }
              }
              Navigator.pop(context);
            },
            child: const Text("VALIDER")),
      ],
    );
  }

  Widget _buildHeatMap(GameProvider game, BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12, width: 1),
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 14,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 1.0),
        itemCount: 70,
        itemBuilder: (context, index) {
          final dateToShow = today.subtract(Duration(days: 69 - index));
          final dateKey = dateToShow.toIso8601String().split('T')[0];
          Map<String, dynamic>? data = game.calendarHistory[dateKey];
          Color boxColor = Colors.white.withOpacity(0.04);
          Border? boxBorder = Border.all(color: Colors.white10, width: 0.8);

          if (data != null) {
            if (data['status'] == 'gold') {
              boxColor = const Color(0xFFFFD700);
              boxBorder = Border.all(color: const Color(0xFFFFD700), width: 1);
            } else if (data['status'] == 'blue') {
              boxColor = const Color(0xFF00E5FF);
              boxBorder = Border.all(color: const Color(0xFF00E5FF), width: 1);
            }
          }

          return GestureDetector(
            onLongPress: game.isGodMode
                ? () => _showEditHistoryDialog(context, game, dateKey)
                : null,
            child: Container(
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: BorderRadius.circular(2),
                border: (index == 69)
                    ? Border.all(color: const Color(0xFF00E5FF), width: 1.5)
                    : boxBorder,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditHistoryDialog(
      BuildContext context, GameProvider game, String dateKey) {
    SystemDialog.show(
      context,
      title: "JOUR : $dateKey",
      content: const Text("Modifier l'etat de ce jour ?",
          style: TextStyle(color: Colors.white70)),
      actions: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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
            child:
                Container(width: 30, height: 30, color: const Color(0xFF00E5FF)),
          ),
          InkWell(
            onTap: () {
              game.updateHistoryStatus(dateKey, 'gold');
              Navigator.pop(context);
            },
            child:
                Container(width: 30, height: 30, color: const Color(0xFFFFD700)),
          ),
          InkWell(
            onTap: () {
              game.updateHistoryStatus(dateKey, 'grey');
              Navigator.pop(context);
            },
            child:
                Container(width: 30, height: 30, color: const Color(0xFF1A1A2E)),
          ),
        ])
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: color.withOpacity(0.5)))),
      child: Center(
          child: Text(title,
              style: GoogleFonts.orbitron(
                  color: color,
                  fontSize: 20,
                  letterSpacing: 10,
                  fontWeight: FontWeight.bold))),
    );
  }

  Widget _buildStatusLine(
      String label, int val, int max, Color color, BuildContext context,
      {bool isEditable = false, GameProvider? game, String? stat}) {
    double progress = (max > 0) ? (val / max).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      onLongPress: (isEditable && game != null && game.isGodMode)
          ? () => _showEditStatDialog(context, game, stat ?? label)
          : null,
      child: Row(
        children: [
          SizedBox(
              width: 35,
              child: Text(label,
                  style: GoogleFonts.orbitron(
                      color: color, fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                      height: 10,
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(2))),
                  Container(
                      height: 10,
                      width: constraints.maxWidth * progress,
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                                color: color.withOpacity(0.5), blurRadius: 5)
                          ])),
                ],
              );
            }),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text("${_formatStat(val)}/${_formatStat(max)}",
                textAlign: TextAlign.right,
                style: GoogleFonts.rajdhani(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSurpassement(
      BuildContext context, GameProvider game, int value) {
    String displayValue = value.toString();
    if (value >= 1000) {
      displayValue = "${(value / 1000).toStringAsFixed(1)} K";
    }
    return GestureDetector(
      onLongPress: game.isGodMode
          ? () => _showEditStatDialog(context, game, "SURPASSEMENT")
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.bolt,
              color: game.isGodMode ? Colors.redAccent : Colors.yellowAccent,
              size: 16),
          const SizedBox(width: 5),
          Text(
            "SURPASSEMENT: $displayValue",
            style: GoogleFonts.orbitron(
              color: Colors.cyanAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              shadows: [const Shadow(color: Colors.cyan, blurRadius: 5)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveList(
      BuildContext context, GameProvider game, Color systemBlue) {
    return Column(
      children: [
        Text("ARCHIVES DU SYSTEME",
            style: GoogleFonts.orbitron(
                color: systemBlue,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: game.saveHistory.length,
          itemBuilder: (ctx, i) {
            final item = game.saveHistory[i];
            return ListTile(
              title: Text("Sequence du ${_formatDate(item['date'])}",
                  style: GoogleFonts.rajdhani(color: Colors.white)),
              trailing:
                  const Icon(Icons.copy, color: Colors.white24, size: 16),
              onTap: () {
                Clipboard.setData(ClipboardData(text: item['code']));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("Copie !")));
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSystemButtons(
      BuildContext context, GameProvider game, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _holoButton(
                "EXPORTER SAUVEGARDE",
                color,
                () {
                  Clipboard.setData(ClipboardData(text: game.exportSaveCode()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "Code de sauvegarde copie ! Conservez-le en lieu sur."),
                      backgroundColor: Color(0xFF00FF66),
                    ),
                  );
                },
                icon: Icons.cloud_upload_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _holoButton(
                "IMPORTER SAUVEGARDE",
                Colors.redAccent,
                () => _showImportDialog(context, game),
                icon: Icons.cloud_download_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          "Generez un code de secours pour ne jamais perdre votre progression en changeant de telephone.",
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _holoButton(String text, Color color, VoidCallback onTap,
      {IconData? icon}) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          side: BorderSide(color: color.withOpacity(0.6), width: 1.2),
          backgroundColor: color.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.orbitron(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context, GameProvider game) {
    final controller = TextEditingController();
    SystemDialog.show(
      context,
      title: "SYNCHRONISATION",
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ANNULER")),
        TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final bool ok = await game.importSaveCode(controller.text);
            if (context.mounted) Navigator.pop(context);
            messenger.showSnackBar(
              SnackBar(
                content: Text(ok
                    ? "Sauvegarde importee."
                    : "Code invalide : rien n'a ete modifie."),
                backgroundColor: ok ? null : Colors.red,
              ),
            );
          },
          child: const Text("VALIDER"),
        ),
      ],
    );
  }

  void _showShopDialog(BuildContext context, GameProvider game) {
    SystemDialog.show(
      context,
      title: "BOUTIQUE DU SYSTEME",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildShopItem(context, game, "Potion Mineure", "Soigne 50 PV",
              game.priceMinorPotion, "mineure"),
          _buildShopItem(context, game, "Potion Majeure", "Soigne 200 PV",
              game.priceMajorPotion, "majeure"),
          _buildShopItem(context, game, "Elixir Royal", "Restaure 100% des PV",
              game.priceFullHeal, "guerison"),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text("FERMER"))
      ],
    );
  }

  Widget _buildShopItem(BuildContext ctx, GameProvider game, String name,
      String desc, int price, String id) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.local_drink_outlined,
            color: Color(0xFF00E5FF), size: 22),
        title: Text(name,
            style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        subtitle: Text(desc,
            style: GoogleFonts.rajdhani(color: Colors.white60, fontSize: 12)),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFFD700)),
            backgroundColor: const Color(0xFFFFD700).withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () {
            if (game.currentHealth >= game.maxHealth) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text("Sante deja au maximum."),
                    backgroundColor: Colors.blueAccent),
              );
              return;
            }
            bool success = game.buyItem(id);
            if (success) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text("Ravitaillement consomme."),
                    duration: Duration(seconds: 1)),
              );
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text("Or insuffisant."),
                    backgroundColor: Colors.red),
              );
            }
          },
          child: Text("$price OR",
              style: GoogleFonts.orbitron(
                  color: const Color(0xFFFFD700),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}