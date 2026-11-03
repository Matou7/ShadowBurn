// lib/main.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

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

import 'widgets/urgent_quest_overlay.dart';
import 'widgets/penalty_overlay.dart';
import 'widgets/dungeon_result_overlay.dart';

const bool kForceDungeonOnBoot = false;
const bool kForceDungeonRed    = false;
const bool kForcePenaltyOnBoot = false;
const bool kForceIntroOnBoot   = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyCEDUjIjkclLQzyqxLnZPmrgGcHhzPEzUI",
          authDomain: "shadowburn-1d8f8.firebaseapp.com",
          projectId: "shadowburn-1d8f8",
          storageBucket: "shadowburn-1d8f8.firebasestorage.app",
          messagingSenderId: "1045603092576",
          appId: "1:1045603092576:web:7a4707409f3976d4b9db05",
        ),
      );
    } catch (e) {
      debugPrint("Erreur initialisation Firebase Web: $e");
    }

    runApp(const ShadowBurnTvApp());
    return;
  }

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCEDUjIjkclLQzyqxLnZPmrgGcHhzPEzUI",
        authDomain: "shadowburn-1d8f8.firebaseapp.com",
        projectId: "shadowburn-1d8f8",
        storageBucket: "shadowburn-1d8f8.firebasestorage.app",
        messagingSenderId: "1045603092576",
        appId: "1:1045603092576:web:7a4707409f3976d4b9db05",
      ),
    );
  } catch (e) {
    debugPrint("Erreur init Firebase Android: $e");
  }

  final prefs = await SharedPreferences.getInstance();
  final bool introAlreadyDone = prefs.getBool('has_completed_intro') ?? false;

  final Map<String, dynamic>? godSave = await SandboxManager.loadSandbox();
  final bool isPersistentGod = godSave != null && godSave['godModePersistPenalty'] == true;

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
    final Map<String, dynamic> nativePenalty = await StorageService.readPenaltyState();
    final bool nativePenaltyActive = nativePenalty['active'] == true;

    // Native Cerberus state is authoritative even if every RPG save is missing
    // or corrupt. Never unlock during bootstrap while this independent lock is active.
    if (penaltyInReal || nativePenaltyActive || kForcePenaltyOnBoot) {
      startsInPenalty = true;
      final dynamic nativeDone = nativePenalty['squatsDone'];
      final dynamic nativeGoal = nativePenalty['squatsGoal'];
      initialSquatsDone = nativePenaltyActive && nativeDone is num
          ? nativeDone.toInt()
          : (realData?['penaltySquats'] as num?)?.toInt() ?? 0;
      initialSquatsGoal = nativePenaltyActive && nativeGoal is num
          ? nativeGoal.toInt()
          : (realData?['penaltyGoal'] as num?)?.toInt() ?? 100;
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
    if (fullUrl.contains('admin') || frag.contains('admin')) {
      initial = '/admin';
    } else if (fullUrl.contains('join') || frag.contains('join')) {
      initial = '/join';
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

        if (settings.name == '/admin' ||
            currentUrl.contains('admin') ||
            fragment.contains('admin')) {
          return MaterialPageRoute(builder: (_) => const AdminScreen());
        }

        if (settings.name == '/join' ||
            currentUrl.contains('join') ||
            fragment.contains('join')) {
          return MaterialPageRoute(builder: (_) => const HunterJoinScreen());
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

class _ShadowBurnAppState extends State<ShadowBurnApp> {
  static const MethodChannel _intentChannel = MethodChannel('com.shadowburn.app/intents');

  @override
  void initState() {
    super.initState();
    _handleIncomingIntent();
  }

  Future<void> _handleIncomingIntent() async {
    try {
      final String? initialLink = await _intentChannel.invokeMethod<String>('getInitialLink');
      if (initialLink != null && initialLink.isNotEmpty) {
        _routeDeepLink(initialLink);
      }
    } catch (_) {}

    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntent') {
        final String? link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          _routeDeepLink(link);
        }
      }
    });
  }

  void _routeDeepLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return;

    if (uri.host == 'admin' || uri.path.contains('admin')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final game = Provider.of<GameProvider>(context, listen: false);
        if (!game.isPro) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("ACCÈS TÉLÉCOMMANDE REFUSÉ : STATUT MONARQUE REQUIS"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    final bool introDone = kForceIntroOnBoot ? false : (prefs.getBool('has_completed_intro') ?? false);

    final PermissionStatus overlay = await Permission.systemAlertWindow.status;
    final PermissionStatus activity = await Permission.activityRecognition.status;

    bool notifsGranted = false;
    try {
      final bool? resNotifs = await _platform.invokeMethod<bool>('checkAllNotificationsEnabled');
      notifsGranted = resNotifs ?? false;
    } catch (_) {
      final PermissionStatus notifs = await Permission.notification.status;
      notifsGranted = notifs.isGranted;
    }

    bool usageStatsGranted = false;
    try {
      final bool? resUsage = await _platform.invokeMethod<bool>('checkUsagePermission');
      usageStatsGranted = resUsage ?? false;
    } catch (_) {
      usageStatsGranted = false;
    }

    bool batteryGranted = false;
    try {
      final bool? resBattery = await _platform.invokeMethod<bool>('checkBatteryOptimizations');
      batteryGranted = resBattery ?? false;
    } catch (_) {
      final PermissionStatus batteryStatus = await Permission.ignoreBatteryOptimizations.status;
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
          final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
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
  bool _hasReconciledNativeLock = false;

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
      if (game.isInPenaltyZone || game.isInDungeon ||
          game.isDungeonFinishing || game.isPenaltyCompleting) {
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

    final bool shouldLock = game.isInPenaltyZone ||
        game.isInDungeon ||
        game.isDungeonFinishing ||
        game.isPenaltyCompleting;
    if (game.isLoaded) {
      if (!_hasReconciledNativeLock) {
        // Reconcile a lock restored by Android with the authoritative saved game state.
        _hasReconciledNativeLock = true;
        _lastLockState = shouldLock;
        if (shouldLock) {
          LockService.lockScreen(force: true);
        } else {
          LockService.unlockScreen(force: true);
        }
      } else {
        _syncNativeLock(shouldLock);
      }
    }

    if (!game.isLoaded && !game.isInPenaltyZone && !game.isInDungeon) {
      return const _LoadingScreen();
    }

    if (game.isDungeonFinishing || game.isPenaltyCompleting) {
      final String statusText = game.isDungeonFinishing
          ? "VALIDATION DU DONJON..."
          : "VALIDATION DE LA PÉNALITÉ...";
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                const SizedBox(height: 20),
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (game.isGodMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: Colors.redAccent.withValues(alpha: 0.85),
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