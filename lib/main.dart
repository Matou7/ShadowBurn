import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'providers/game_provider.dart';
import 'providers/urgent_quest_provider.dart';
import 'services/notification_service.dart';
import 'services/lock_service.dart';
import 'services/storage_service.dart';
import 'services/sandbox_manager.dart';
import 'services/midnight_executor.dart';

import 'screens/stats_quests_screen.dart';
import 'screens/inventory_dungeon_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/class_change_quest_screen.dart';
import 'screens/permission_guide_screen.dart';
import 'screens/intro_awakening_screen.dart';
import 'screens/arena_tv_screen.dart';
import 'screens/hunter_join_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/raid_admin_panel_screen.dart';

import 'widgets/urgent_quest_overlay.dart';
import 'widgets/penalty_overlay.dart';
import 'widgets/dungeon_result_overlay.dart';

const bool kForceDungeonOnBoot = false;
const bool kForceDungeonRed = false;
const bool kForcePenaltyOnBoot = false;
const bool kForceIntroOnBoot = false;

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

const FirebaseOptions _shadowBurnFirebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyCEDUjIjkclLQzyqxLnZPmrgGcHhzPEzUI",
  authDomain: "shadowburn-1d8f8.firebaseapp.com",
  projectId: "shadowburn-1d8f8",
  storageBucket: "shadowburn-1d8f8.firebasestorage.app",
  messagingSenderId: "1045603092576",
  appId: "1:1045603092576:web:7a4707409f3976d4b9db05",
);

bool _isLanOrSoloWebUrl(String urlLower, String fragLower) {
  return urlLower.contains('mode=lan') ||
      urlLower.contains('ws=') ||
      urlLower.contains('solo=1') ||
      urlLower.contains('local=1') ||
      urlLower.contains('solo_local') ||
      urlLower.contains('/solo') ||
      fragLower.contains('mode=lan') ||
      fragLower.contains('ws=') ||
      fragLower.contains('solo=1') ||
      fragLower.contains('local=1') ||
      fragLower.contains('solo_local') ||
      fragLower.contains('/solo');
}

Future<void> _ensureSilentFirebaseAuth() async {
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 5));
    }
  } catch (e) {
    debugPrint("Avertissement Auth Anonyme Silencieuse: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    final String fullUrl = Uri.base.toString().toLowerCase();
    final String frag = Uri.base.fragment.toLowerCase();
    final bool skipFirebaseWeb = _isLanOrSoloWebUrl(fullUrl, frag);

    if (!skipFirebaseWeb) {
      try {
        await Firebase.initializeApp(
          options: _shadowBurnFirebaseOptions,
        );
        await _ensureSilentFirebaseAuth();
      } catch (e) {
        debugPrint("Erreur initialisation Firebase Web: $e");
      }
    }

    runApp(const ShadowBurnTvApp());
    return;
  }

  try {
    await Firebase.initializeApp(
      options: _shadowBurnFirebaseOptions,
    );
    await _ensureSilentFirebaseAuth();
  } catch (e) {
    debugPrint("Erreur initialisation Firebase Android: $e");
  }

  final prefs = await SharedPreferences.getInstance();
  final bool introAlreadyDone = prefs.getBool('has_completed_intro') ?? false;

  final Map<String, dynamic>? godSave = await SandboxManager.loadSandbox();
  final bool isPersistentGod =
      godSave != null && godSave['godModePersistPenalty'] == true;

  bool startsInPenalty = false;
  int initialSquatsDone = 0;
  int initialSquatsGoal = 100;

  if (isPersistentGod) {
    SandboxManager.isSandboxActive = true;
    SandboxManager.persistPenalty = true;
    StorageService.blockAllRealSaves = true;

    startsInPenalty = godSave['penaltyActive'] == true;
    initialSquatsDone = (godSave['penaltySquats'] as num?)?.toInt() ?? 0;
    initialSquatsGoal = (godSave['penaltyGoal'] as num?)?.toInt() ?? 100;
  } else {
    await SandboxManager.exitSandbox(keepChanges: false);

    final LoadedSave? realSave = await StorageService.load();
    final Map<String, dynamic>? realData = realSave?.data;
    final bool penaltyInReal = realData?['penaltyActive'] == true;

    if (penaltyInReal || kForcePenaltyOnBoot) {
      final penaltyState = await StorageService.readPenaltyState();
      startsInPenalty = true;
      initialSquatsDone = (penaltyState['squatsDone'] as int?) ??
          (realData?['penaltySquats'] as int?) ??
          0;
      initialSquatsGoal = (penaltyState['squatsGoal'] as int?) ??
          (realData?['penaltyGoal'] as int?) ??
          100;
      if (initialSquatsGoal <= 0) initialSquatsGoal = 100;
    } else {
      startsInPenalty = false;
      await SandboxManager.clearNativePenalty();
    }
  }

  final bool shouldLockAtBoot = startsInPenalty || kForceDungeonOnBoot;
  if (shouldLockAtBoot) {
    try {
      await LockService.lockScreen(force: true);
    } catch (_) {}
  } else {
    try {
      await LockService.unlockScreen(force: true);
    } catch (_) {}
  }

  try {
    await NotificationService.init();
  } catch (_) {}

  try {
    await MidnightExecutor.init();
  } catch (_) {}

  if (introAlreadyDone) {
    try {
      await NotificationService.updateTrackingNotification(
        "Le Système veille.",
        "Suivi des pas et de la Forge actifs",
        color: const Color(0xFF00E5FF),
        progress: 0,
        maxProgress: 100,
      );
    } catch (_) {}
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UrgentQuestProvider()),
        ChangeNotifierProxyProvider<UrgentQuestProvider, GameProvider>(
          create: (_) {
            final game = GameProvider();

            if (startsInPenalty) {
              game.restorePenaltyState(initialSquatsDone, initialSquatsGoal);
            }

            if (kForceDungeonOnBoot && !startsInPenalty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (game.activeDungeon == null) {
                  game.enterDungeon(
                    game.rank,
                    isThreat: true,
                    isRed: kForceDungeonRed,
                  );
                }
              });
            }

            return game;
          },
          update: (_, urgent, game) {
            final gameInstance = game ?? GameProvider();
            gameInstance.setUrgentQuestProvider(urgent);
            return gameInstance;
          },
        ),
      ],
      child: const ShadowBurnApp(),
    ),
  );
}

class ShadowBurnTvApp extends StatelessWidget {
  const ShadowBurnTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final String fullUrl = Uri.base.toString().toLowerCase();
    final String frag = Uri.base.fragment.toLowerCase();

    String initial = '/';
    if (fullUrl.contains('role=hunter') ||
        frag.contains('role=hunter') ||
        fullUrl.contains('join') ||
        frag.contains('join')) {
      initial = '/join';
    } else if (_isLanOrSoloWebUrl(fullUrl, frag)) {
      initial = '/lan';
    } else if (fullUrl.contains('admin') || frag.contains('admin')) {
      initial = '/admin';
    }

    return MaterialApp(
      title: 'ShadowBurn Arena TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF02070D),
        fontFamily: 'monospace',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF2E56),
          surface: Color(0xFF04101E),
        ),
      ),
      initialRoute: initial,
      onGenerateRoute: (settings) {
        final String currentUrl = Uri.base.toString().toLowerCase();
        final String fragment = Uri.base.fragment.toLowerCase();

        if (settings.name == '/join' ||
            currentUrl.contains('join') ||
            fragment.contains('join') ||
            currentUrl.contains('role=hunter') ||
            fragment.contains('role=hunter')) {
          return MaterialPageRoute(builder: (_) => const HunterJoinScreen());
        }

        if (settings.name == '/lan' ||
            settings.name == '/solo' ||
            _isLanOrSoloWebUrl(currentUrl, fragment)) {
          return MaterialPageRoute(builder: (_) => const ArenaTvScreen());
        }

        if (settings.name == '/admin' ||
            currentUrl.contains('admin') ||
            fragment.contains('admin')) {
          return MaterialPageRoute(builder: (_) => const AdminScreen());
        }

        return MaterialPageRoute(builder: (_) => const ArenaTvScreen());
      },
    );
  }
}

class ShadowBurnApp extends StatefulWidget {
  const ShadowBurnApp({super.key});

  @override
  State<ShadowBurnApp> createState() => _ShadowBurnAppState();
}

class _ShadowBurnAppState extends State<ShadowBurnApp>
    with WidgetsBindingObserver {
  static const MethodChannel _intentChannel =
      MethodChannel('com.shadowburn.app/intents');
  static const MethodChannel _lockChannel =
      MethodChannel('com.shadowburn.app/lock');

  bool _isShowingProPopup = false;
  bool _isHandlingIntent = false;
  String? _lastHandledLink;
  int _lastHandledTimestampMs = 0;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMethodCallHandler();
    _handleIncomingIntent();
    _checkWebProSuccessUrl();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleIncomingIntent();
      _silentCheckHardwarePurchase();
    }
  }

  void _setupMethodCallHandler() {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntent') {
        final String? link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          _routeDeepLink(link);
        }
      }
    });
  }

  void _checkWebProSuccessUrl() {
    if (!kIsWeb) return;
    final Uri currentUri = Uri.base;
    final String fullStr = currentUri.toString().toLowerCase();
    final String fragment = currentUri.fragment.toLowerCase();

    if (fullStr.contains('pro-success') || fragment.contains('pro-success')) {
      final Map<String, String> params = currentUri.queryParameters;
      String sessionKey = params['key'] ?? params['session_id'] ?? '';

      if (sessionKey.isEmpty && fragment.contains('?')) {
        try {
          final fragQuery = fragment.split('?').last;
          final uriParams = Uri.splitQueryString(fragQuery);
          sessionKey = uriParams['key'] ?? uriParams['session_id'] ?? '';
        } catch (_) {}
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _isShowingProPopup) return;
        final game = Provider.of<GameProvider>(context, listen: false);

        if (sessionKey.isNotEmpty) {
          await game.activateProKey(sessionKey);
        } else {
          await game.requestHardwareAutoRecovery();
        }

        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted && !_isShowingProPopup) {
          _showProSuccessDialog(ctx,
              game.licenseKey.isNotEmpty ? game.licenseKey : "PASS-PRO-ACTIVÉ");
        }
      });
    }
  }

  Future<void> _silentCheckHardwarePurchase() async {
    if (!mounted || _isShowingProPopup) return;
    final game = Provider.of<GameProvider>(context, listen: false);
    if (await game.ensureProStatusLoaded()) return;

    final bool recovered = await game.requestHardwareAutoRecovery();
    if (recovered && mounted && !_isShowingProPopup) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _showProSuccessDialog(ctx,
            game.licenseKey.isNotEmpty ? game.licenseKey : "PASS-PRO-ACTIVÉ");
      }
    }
  }

  Future<void> _handleIncomingIntent() async {
    if (_isHandlingIntent) return;
    _isHandlingIntent = true;

    try {
      String? link;
      try {
        link = await _intentChannel
            .invokeMethod<String>('getInitialLink')
            .timeout(const Duration(seconds: 2));
      } catch (_) {}

      if (link == null || link.isEmpty) {
        try {
          link = await _lockChannel
              .invokeMethod<String>('getInitialIntentUrl')
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      if (link != null && link.isNotEmpty) {
        _routeDeepLink(link);
      }
    } finally {
      _isHandlingIntent = false;
    }
  }

  void _routeDeepLink(String rawLink) {
    final String link = rawLink.trim();
    if (link.isEmpty) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastHandledLink == link && (nowMs - _lastHandledTimestampMs) < 3000) {
      return;
    }
    _lastHandledLink = link;
    _lastHandledTimestampMs = nowMs;

    final uri = Uri.tryParse(link);
    if (uri == null) return;

    if (uri.host == 'pro-success' || uri.path.contains('pro-success')) {
      final String urlKey =
          (uri.queryParameters['key'] ?? uri.queryParameters['session_id'] ?? '')
              .trim()
              .toUpperCase();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _isShowingProPopup) return;
        final game = Provider.of<GameProvider>(context, listen: false);
        String activeKey = urlKey;

        if (activeKey.isNotEmpty) {
          await game.activateProKey(activeKey);
        } else {
          final bool recovered = await game.requestHardwareAutoRecovery();
          if (recovered && game.licenseKey.isNotEmpty) {
            activeKey = game.licenseKey;
          }
        }

        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted && !_isShowingProPopup) {
          _showProSuccessDialog(
              ctx, activeKey.isNotEmpty ? activeKey : "PASS-PRO-ACTIVÉ");
        }
      });
      return;
    }

    if (uri.host == 'admin' ||
        uri.path.contains('admin') ||
        link.contains('room=') ||
        link.contains('mode=lan') ||
        link.contains('ws=')) {
      String? roomId = uri.queryParameters['room'];
      String? adminKey = uri.queryParameters['key'];
      String? mode = uri.queryParameters['mode'];
      String? ws = uri.queryParameters['ws'];

      if (uri.fragment.contains('?')) {
        try {
          final fragParams = Uri.splitQueryString(uri.fragment.split('?').last);
          roomId ??= fragParams['room'];
          adminKey ??= fragParams['key'];
          mode ??= fragParams['mode'];
          ws ??= fragParams['ws'];
        } catch (_) {}
      }

      final String cleanMode =
          (mode ?? ((ws != null && ws.isNotEmpty) ? 'lan' : 'cloud'))
              .trim()
              .toLowerCase();
      final String decodedWs = (ws != null && ws.trim().isNotEmpty)
          ? Uri.decodeComponent(ws.trim())
          : '';
      final bool isLan = cleanMode == 'lan' || decodedWs.isNotEmpty;
      final String cleanRoom = (roomId ?? (isLan ? 'LAN_1' : '')).trim();
      final String cleanKey = (adminKey ?? '').trim();

      if (cleanRoom.isEmpty && !isLan) return;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final ctx = rootNavigatorKey.currentContext;
        final game = Provider.of<GameProvider>(context, listen: false);

        if (isLan) {
          final prefs = await SharedPreferences.getInstance();
          final parsedWs = Uri.tryParse(decodedWs);
          if (parsedWs != null && parsedWs.host.isNotEmpty) {
            await prefs.setString('shadow_lan_host_ip', parsedWs.host);
          }
          final String resolvedRoom = cleanRoom.isEmpty ? 'LAN_1' : cleanRoom;
          await prefs.setString('shadow_lan_active_room', resolvedRoom);
          await prefs.setString('shadow_lan_active_ws', decodedWs);

          final nav = rootNavigatorKey.currentState;
          if (nav != null && nav.mounted) {
            nav.push(
              MaterialPageRoute(
                builder: (_) => RaidAdminPanelScreen(
                  roomId: resolvedRoom,
                  adminKey: cleanKey.isNotEmpty ? cleanKey : 'LAN',
                ),
              ),
            );
          }
          return;
        }

        final bool isProVerified = await game.ensureProStatusLoaded();

        if (!isProVerified) {
          if (ctx != null && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text(
                    "ACCÈS REFUSÉ : TÉLÉCOMMANDE RÉSERVÉE AU MODE MONARQUE PRO."),
                backgroundColor: Color(0xFFFF2E56),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        await game.pairAdminRoom(cleanRoom, adminKey: cleanKey);
      });
    }
  }

  void _showProSuccessDialog(BuildContext dialogContext, String licenseKey) {
    if (_isShowingProPopup) return;
    _isShowingProPopup = true;

    Clipboard.setData(ClipboardData(text: licenseKey));

    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 2), () {
      if (_isShowingProPopup) {
        _isShowingProPopup = false;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && Navigator.canPop(ctx)) {
          Navigator.pop(ctx);
        }
      }
    });

    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF121217),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF00FF66), width: 2),
            ),
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified, color: Color(0xFF00FF66), size: 28),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    "ÉVEIL MONARQUE RÉUSSI",
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      color: Color(0xFF00FF66),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Statut Pro activé avec succès.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                const Text(
                  "VOTRE CLÉ DE LICENCE :",
                  style: TextStyle(
                      fontFamily: 'Orbitron',
                      color: Color(0xFF00E5FF),
                      fontSize: 10,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border:
                        Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    licenseKey,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF66),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Fermeture automatique...",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
            actions: const [],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'ShadowBurn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Rajdhani',
        primaryColor: const Color(0xFF00E5FF),
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'Rajdhani', color: Colors.white),
          bodyMedium: TextStyle(fontFamily: 'Rajdhani', color: Colors.white),
          displayLarge: TextStyle(fontFamily: 'Rajdhani', color: Colors.white),
          displayMedium: TextStyle(fontFamily: 'Rajdhani', color: Colors.white),
          titleLarge: TextStyle(fontFamily: 'Orbitron', color: Colors.white),
          titleMedium: TextStyle(fontFamily: 'Orbitron', color: Colors.white),
        ),
      ),
      home: const RootPermissionGateway(),
    );
  }
}

class RootPermissionGateway extends StatefulWidget {
  const RootPermissionGateway({super.key});

  @override
  State<RootPermissionGateway> createState() => _RootPermissionGatewayState();
}

class _RootPermissionGatewayState extends State<RootPermissionGateway>
    with WidgetsBindingObserver {
  static const MethodChannel _platform = MethodChannel('com.shadowburn.app/lock');

  bool _isLoading = true;
  bool _hasAllPermissions = false;
  bool _hasCompletedIntro = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluateGate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluateGate();
    }
  }

  Future<void> _evaluateGate() async {
    final prefs = await SharedPreferences.getInstance();
    final bool introDone = kForceIntroOnBoot
        ? false
        : (prefs.getBool('has_completed_intro') ?? false);

    final PermissionStatus overlay = await Permission.systemAlertWindow.status;
    final PermissionStatus activity = await Permission.activityRecognition.status;

    bool notifsGranted = false;
    try {
      final bool? resNotifs =
          await _platform.invokeMethod<bool>('checkAllNotificationsEnabled');
      notifsGranted = resNotifs ?? false;
    } catch (_) {
      final PermissionStatus notifs = await Permission.notification.status;
      notifsGranted = notifs.isGranted;
    }

    bool usageStatsGranted = false;
    try {
      final bool? resUsage =
          await _platform.invokeMethod<bool>('checkUsagePermission');
      usageStatsGranted = resUsage ?? false;
    } catch (_) {
      usageStatsGranted = false;
    }

    bool batteryGranted = false;
    try {
      final bool? resBattery =
          await _platform.invokeMethod<bool>('checkBatteryOptimizations');
      batteryGranted = resBattery ?? false;
    } catch (_) {
      final PermissionStatus batteryStatus =
          await Permission.ignoreBatteryOptimizations.status;
      batteryGranted = batteryStatus.isGranted;
    }

    final bool allGranted = overlay.isGranted &&
        activity.isGranted &&
        notifsGranted &&
        usageStatsGranted &&
        batteryGranted;

    if (!mounted) return;
    setState(() {
      _hasAllPermissions = allGranted;
      _hasCompletedIntro = introDone;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _LoadingScreen();
    }

    if (!_hasAllPermissions) {
      return PermissionGuideScreen(
        onPermissionsGranted: () {
          setState(() {
            _hasAllPermissions = true;
          });
        },
      );
    }

    if (!_hasCompletedIntro) {
      return IntroAwakeningScreen(
        onIntroComplete: (hunterName) {
          final game = context.read<GameProvider>();
          game.updateUsername(hunterName);
          final now = DateTime.now();
          final todayStr =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          game.initializeFirstDay(todayStr);

          setState(() {
            _hasCompletedIntro = true;
          });
        },
      );
    }

    return const GameWrapper();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E5FF)),
            SizedBox(height: 20),
            Text(
              "CHARGEMENT DU SYSTÈME...",
              style: TextStyle(
                fontFamily: 'Orbitron',
                color: Color(0xFF00E5FF),
                fontSize: 12,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameWrapper extends StatefulWidget {
  const GameWrapper({super.key});

  @override
  State<GameWrapper> createState() => _GameWrapperState();
}

class _GameWrapperState extends State<GameWrapper> with WidgetsBindingObserver {
  bool _lastLockState = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      LockService.cancelEmergencyExemption();
      final game = context.read<GameProvider>();
      if (game.isInPenaltyZone || game.isInDungeon) {
        LockService.lockScreen(force: true);
      }
    }
  }

  void _syncNativeLock(bool shouldLock) {
    if (shouldLock != _lastLockState) {
      _lastLockState = shouldLock;
      if (shouldLock) {
        LockService.lockScreen(force: true);
      } else {
        LockService.unlockScreen(force: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    final bool shouldLock = game.isInPenaltyZone || game.isInDungeon;
    _syncNativeLock(shouldLock);

    if (!game.isLoaded && !game.isInPenaltyZone && !game.isInDungeon) {
      return const _LoadingScreen();
    }

    if (game.isInPenaltyZone) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PenaltyOverlay(),
        ),
      );
    }

    if (game.isClassChangeActive) return const ClassChangeQuestScreen();

    if (game.isInDungeon) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              InventoryDungeonScreen(),
              UrgentQuestOverlay(),
            ],
          ),
        ),
      );
    }

    if (game.dungeonResult != null) return const DungeonResultOverlay();

    return const MainScaffold();
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  final PageController _pageController = PageController(initialPage: 0);
  int _activePage = 0;
  String? _lastSwitchedRoom;

  final List<Widget> _screens = [
    const StatsQuestsScreen(),
    const InventoryDungeonScreen(),
    const ProfileScreen(),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    const Color systemBlue = Color(0xFF00E5FF);

    final String? pairedRoom = game.pairedAdminRoom;
    if (game.isPro &&
        pairedRoom != null &&
        pairedRoom.isNotEmpty &&
        _lastSwitchedRoom != pairedRoom) {
      _lastSwitchedRoom = pairedRoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients && _activePage != 2) {
          _pageController.animateToPage(
            2,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } else if (pairedRoom == null || pairedRoom.isEmpty) {
      _lastSwitchedRoom = null;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (game.isGodMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: Colors.redAccent.withOpacity(0.85),
                child: const Text(
                  "BAC À SABLE : RIEN N'EST ENREGISTRÉ",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  PageView(
                    controller: _pageController,
                    onPageChanged: (int page) {
                      setState(() {
                        _activePage = page;
                      });
                    },
                    children: _screens,
                  ),
                  const UrgentQuestOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 40,
        color: Colors.black,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_screens.length, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              height: 2,
              width: _activePage == index ? 30 : 10,
              decoration: BoxDecoration(
                color: _activePage == index ? systemBlue : Colors.white10,
                boxShadow: _activePage == index
                    ? [const BoxShadow(color: systemBlue, blurRadius: 5)]
                    : [],
              ),
            );
          }),
        ),
      ),
    );
  }
}