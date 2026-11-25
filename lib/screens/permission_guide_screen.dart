// lib/screens/permission_guide_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/lock_service.dart';

class PermissionGuideScreen extends StatefulWidget {
  final VoidCallback onPermissionsGranted;

  const PermissionGuideScreen({super.key, required this.onPermissionsGranted});

  @override
  State<PermissionGuideScreen> createState() => _PermissionGuideScreenState();
}

class _PermissionGuideScreenState extends State<PermissionGuideScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _platform = MethodChannel('com.shadowburn.app/lock');

  bool _isChecking = false;

  bool _hasActivity = false;
  bool _hasNotifications = false;
  bool _hasOverlay = false;
  bool _hasUsageStats = false;
  bool _hasBatteryExemption = false;
  bool _hasTermuxRunCommand = false;
  bool _hasCamera = false;
  bool _hasStorageAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<bool> _checkUsageStatsPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? result =
          await _platform.invokeMethod<bool>('checkUsagePermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkBatteryPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? result =
          await _platform.invokeMethod<bool>('checkBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    }
  }

  Future<bool> _checkAllNotifications() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? nativeResult =
          await _platform.invokeMethod<bool>('checkAllNotificationsEnabled');
      if (nativeResult != null) return nativeResult;
    } catch (_) {}

    final PermissionStatus status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<bool> _checkTermuxPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? nativeResult =
          await _platform.invokeMethod<bool>('checkTermuxPermission');
      if (nativeResult != null) return nativeResult;
    } catch (_) {}
    return false;
  }

  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      if (await Permission.storage.isGranted) {
        return true;
      }
      final Directory dir = Directory('/storage/emulated/0/Download/LAN/web');
      await dir.create(recursive: true);
      final File probe = File('/storage/emulated/0/Download/LAN/web/.perm_ok');
      await probe.writeAsString('1', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAllPermissions() async {
    final PermissionStatus activity =
        await Permission.activityRecognition.status;
    final PermissionStatus overlay = await Permission.systemAlertWindow.status;
    final PermissionStatus camera = await Permission.camera.status;

    final bool notifsOk = await _checkAllNotifications();
    final bool usageOk = await _checkUsageStatsPermission();
    final bool batteryOk = await _checkBatteryPermission();
    final bool termuxOk = await _checkTermuxPermission();
    final bool storageOk = await _checkStoragePermission();

    if (!mounted) return;

    setState(() {
      _hasActivity = activity.isGranted;
      _hasNotifications = notifsOk;
      _hasOverlay = overlay.isGranted;
      _hasUsageStats = usageOk;
      _hasBatteryExemption = batteryOk;
      _hasTermuxRunCommand = termuxOk;
      _hasCamera = camera.isGranted;
      _hasStorageAccess = storageOk;
      _isChecking = false;
    });

    final bool s1Ok = _hasActivity && _hasNotifications;
    final bool s2Ok = _hasOverlay && _hasUsageStats;
    final bool s3Ok = _hasBatteryExemption;

    if (s1Ok && s2Ok && s3Ok) {
      widget.onPermissionsGranted();
    }
  }

  Future<void> _handleSector1() async {
    setState(() => _isChecking = true);
    if (!_hasActivity) {
      final status = await Permission.activityRecognition.request();
      if (status.isPermanentlyDenied || status.isDenied) {
        await openAppSettings();
        return;
      }
    }
    if (!_hasNotifications) {
      final status = await Permission.notification.request();
      if (status.isPermanentlyDenied || status.isDenied) {
        await openAppSettings();
        return;
      }
    }
    await _checkAllPermissions();
  }

  Future<void> _handleOverlay() async {
    await LockService.requestOverlayPermission();
    await _checkAllPermissions();
  }

  Future<void> _handleUsageAccessDeep() async {
    try {
      await _platform.invokeMethod('openUsageSettings');
    } catch (_) {
      await openAppSettings();
    }
    await _checkAllPermissions();
  }

  Future<void> _handleBatteryDeep() async {
    setState(() => _isChecking = true);
    final status = await Permission.ignoreBatteryOptimizations.request();

    if (!status.isGranted) {
      try {
        await _platform.invokeMethod('openBatteryNoRestrictions');
      } catch (_) {
        await openAppSettings();
      }
    }

    await _checkAllPermissions();
  }

  Future<void> _handleTermuxPermission() async {
    setState(() => _isChecking = true);
    try {
      final bool? granted =
          await _platform.invokeMethod<bool>('requestTermuxPermission');
      if (granted != true) {
        await openAppSettings();
      }
    } catch (_) {
      await openAppSettings();
    }
    await _checkAllPermissions();
  }

  Future<void> _handleCameraPermission() async {
    setState(() => _isChecking = true);
    final status = await Permission.camera.request();
    if (!status.isGranted && status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkAllPermissions();
  }

  Future<void> _handleStoragePermission() async {
    setState(() => _isChecking = true);
    try {
      final PermissionStatus manageStatus =
          await Permission.manageExternalStorage.request();
      if (!manageStatus.isGranted) {
        final PermissionStatus storageStatus =
            await Permission.storage.request();
        if (!storageStatus.isGranted) {
          await openAppSettings();
        }
      }
    } catch (_) {
      await openAppSettings();
    }
    await _checkAllPermissions();
  }

  Future<void> _handleGlobalValidate() async {
    final bool s1Ok = _hasActivity && _hasNotifications;

    if (!s1Ok) {
      await _handleSector1();
      return;
    }
    if (!_hasOverlay) {
      await _handleOverlay();
      return;
    }
    if (!_hasUsageStats) {
      await _handleUsageAccessDeep();
      return;
    }
    if (!_hasBatteryExemption) {
      await _handleBatteryDeep();
      return;
    }
    await _checkAllPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final bool s1Ok = _hasActivity && _hasNotifications;
    final bool s2Ok = _hasOverlay && _hasUsageStats;
    final bool s3Ok = _hasBatteryExemption;
    final bool allGood = s1Ok && s2Ok && s3Ok;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF00E5FF),
                  size: 50,
                ),
                const SizedBox(height: 10),
                const Text(
                  "ACCÈS MATRICIELS",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Validation physique intégrale. Aucun accès ne peut être ignoré.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      _buildSectorContainer(
                        title: "1. Forge Physique & Radar",
                        subtitle: "ACTIVITY_RECOGNITION • NOTIFICATIONS",
                        description:
                            "Comptabilisation du podomètre et alertes du Système.",
                        isComplete: s1Ok,
                        actionButton: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: s1Ok
                                  ? const Color(0xFF00E5FF)
                                  : Colors.redAccent,
                            ),
                          ),
                          onPressed: _handleSector1,
                          icon: Icon(
                            s1Ok ? Icons.check : Icons.lock_open,
                            color: s1Ok
                                ? const Color(0xFF00E5FF)
                                : Colors.redAccent,
                            size: 16,
                          ),
                          label: Text(
                            s1Ok
                                ? "PODOMÈTRE & NOTIFS : ACTIFS"
                                : "ACTIVER PODOMÈTRE & NOTIFS",
                            style: TextStyle(
                              color: s1Ok
                                  ? const Color(0xFF00E5FF)
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSectorContainer(
                        title: "2. Confinement Cerbère",
                        subtitle: "SYSTEM_ALERT_WINDOW • PACKAGE_USAGE_STATS",
                        description:
                            "Superposition d'écran et accès aux données d'usage pour verrouiller la Pénalité.",
                        isComplete: s2Ok,
                        actionButton: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: _hasOverlay
                                      ? const Color(0xFF00E5FF)
                                      : Colors.redAccent,
                                ),
                              ),
                              onPressed: _handleOverlay,
                              icon: Icon(
                                _hasOverlay ? Icons.check : Icons.layers,
                                color: _hasOverlay
                                    ? const Color(0xFF00E5FF)
                                    : Colors.redAccent,
                                size: 16,
                              ),
                              label: Text(
                                _hasOverlay
                                    ? "SUPERPOSITION : ACCORDÉE"
                                    : "1. ACTIVER : SUPERPOSITION D'ÉCRAN",
                                style: TextStyle(
                                  color: _hasOverlay
                                      ? const Color(0xFF00E5FF)
                                      : Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: _hasUsageStats
                                      ? const Color(0xFF00E5FF)
                                      : Colors.redAccent,
                                ),
                              ),
                              onPressed: _handleUsageAccessDeep,
                              icon: Icon(
                                _hasUsageStats
                                    ? Icons.check
                                    : Icons.query_stats,
                                color: _hasUsageStats
                                    ? const Color(0xFF00E5FF)
                                    : Colors.redAccent,
                                size: 16,
                              ),
                              label: Text(
                                _hasUsageStats
                                    ? "DONNÉES D'USAGE : ACCORDÉES"
                                    : "2. ACTIVER : DONNÉES D'USAGE",
                                style: TextStyle(
                                  color: _hasUsageStats
                                      ? const Color(0xFF00E5FF)
                                      : Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSectorContainer(
                        title: "3. Matrice de Réveil & Zéro Restriction",
                        subtitle: "BATTERY_OPTIMIZATIONS • MATÉRIEL",
                        description:
                            "L'OS exige l'exemption formelle de l'optimisation batterie. Le Système refuse de s'ouvrir tant que le statut physique n'est pas accordé.",
                        isComplete: s3Ok,
                        actionButton: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: s3Ok
                                  ? const Color(0xFF00E5FF)
                                  : Colors.redAccent,
                            ),
                          ),
                          onPressed: _handleBatteryDeep,
                          icon: Icon(
                            s3Ok ? Icons.check : Icons.battery_alert,
                            color: s3Ok
                                ? const Color(0xFF00E5FF)
                                : Colors.redAccent,
                            size: 16,
                          ),
                          label: Text(
                            s3Ok
                                ? "BATTERIE : AUCUNE RESTRICTION (VÉRIFIÉ)"
                                : "AUTORISER L'EXEMPTION DE BATTERIE",
                            style: TextStyle(
                              color: s3Ok
                                  ? const Color(0xFF00E5FF)
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSectorContainer(
                        title: "4. Passerelle Serveur LAN (Optionnel)",
                        subtitle: "COM.TERMUX.PERMISSION.RUN_COMMAND",
                        description:
                            "Permet de démarrer automatiquement le serveur local LAN (TV & Raids Wi-Fi) depuis l'application sans saisir de commandes.",
                        isComplete: _hasTermuxRunCommand,
                        isOptional: true,
                        actionButton: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _hasTermuxRunCommand
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFFF9100),
                            ),
                          ),
                          onPressed: _handleTermuxPermission,
                          icon: Icon(
                            _hasTermuxRunCommand
                                ? Icons.check
                                : Icons.terminal,
                            color: _hasTermuxRunCommand
                                ? const Color(0xFF00FF66)
                                : const Color(0xFFFF9100),
                            size: 16,
                          ),
                          label: Text(
                            _hasTermuxRunCommand
                                ? "COMMANDES TERMUX : AUTORISÉES"
                                : "AUTORISER DANS LES PARAMÈTRES (LAN)",
                            style: TextStyle(
                              color: _hasTermuxRunCommand
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFFF9100),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSectorContainer(
                        title: "5. Accès Fichiers Pack LAN Auto (Optionnel)",
                        subtitle: "MANAGE_EXTERNAL_STORAGE • DOWNLOAD/LAN/WEB",
                        description:
                            "Nécessaire uniquement si tu choisis le mode AUTO pour télécharger et extraire le pack LAN dans Download/LAN/web. Si tu ne l'accordes pas ici, elle te sera redemandée au clic sur AUTO.",
                        isComplete: _hasStorageAccess,
                        isOptional: true,
                        actionButton: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _hasStorageAccess
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFFF9100),
                            ),
                          ),
                          onPressed: _handleStoragePermission,
                          icon: Icon(
                            _hasStorageAccess
                                ? Icons.check
                                : Icons.folder_open,
                            color: _hasStorageAccess
                                ? const Color(0xFF00FF66)
                                : const Color(0xFFFF9100),
                            size: 16,
                          ),
                          label: Text(
                            _hasStorageAccess
                                ? "ACCÈS FICHIERS LAN : AUTORISÉ"
                                : "AUTORISER L'ACCÈS AUX FICHIERS (AUTO)",
                            style: TextStyle(
                              color: _hasStorageAccess
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFFF9100),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSectorContainer(
                        title: "6. Scanner QR Caméra (Optionnel)",
                        subtitle: "CAMERA • SCAN QR SALLE UNIQUEMENT",
                        description:
                            "Utilisée uniquement pour lire les QR codes de salle (mode MULTI / LAN) en direct. Aucune vidéo n'est enregistrée ni sauvegardée, et la saisie manuelle reste toujours disponible.",
                        isComplete: _hasCamera,
                        isOptional: true,
                        actionButton: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _hasCamera
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFFF9100),
                            ),
                          ),
                          onPressed: _handleCameraPermission,
                          icon: Icon(
                            _hasCamera ? Icons.check : Icons.qr_code_scanner,
                            color: _hasCamera
                                ? const Color(0xFF00FF66)
                                : const Color(0xFFFF9100),
                            size: 16,
                          ),
                          label: Text(
                            _hasCamera
                                ? "CAMÉRA QR : AUTORISÉE"
                                : "AUTORISER LA CAMÉRA (QR)",
                            style: TextStyle(
                              color: _hasCamera
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFFF9100),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        allGood ? const Color(0xFF00E5FF) : Colors.grey[900],
                    foregroundColor: allGood ? Colors.black : Colors.white38,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: allGood ? 5 : 0,
                  ),
                  onPressed: allGood ? _handleGlobalValidate : null,
                  child: _isChecking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF00E5FF)),
                        )
                      : Text(
                          allGood
                              ? "MATRICE COMPLÈTE : ENTRER DANS L'ÉVEIL"
                              : "ACCÈS MATRICIELS INCOMPLETS",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    "Aucune simulation tolérée. Verrouillage physique actif.",
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectorContainer({
    required String title,
    required String subtitle,
    required String description,
    required bool isComplete,
    required Widget actionButton,
    bool isOptional = false,
  }) {
    final Color borderColor = isComplete
        ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
        : (isOptional
            ? const Color(0xFFFF9100).withValues(alpha: 0.45)
            : Colors.redAccent.withValues(alpha: 0.4));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(
                isComplete
                    ? Icons.check_circle
                    : (isOptional ? Icons.info_outline : Icons.cancel_outlined),
                color: isComplete
                    ? const Color(0xFF00E5FF)
                    : (isOptional ? const Color(0xFFFF9100) : Colors.redAccent),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 10,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          actionButton,
        ],
      ),
    );
  }
}