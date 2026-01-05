import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; 

import 'providers/game_provider.dart';
import 'providers/urgent_quest_provider.dart';
import 'services/notification_service.dart';

import 'screens/stats_quests_screen.dart'; 
import 'screens/inventory_dungeon_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/class_change_quest_screen.dart';

import 'widgets/urgent_quest_overlay.dart';
import 'widgets/penalty_overlay.dart';
import 'widgets/dungeon_result_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UrgentQuestProvider()),
        ChangeNotifierProxyProvider<UrgentQuestProvider, GameProvider>(
          create: (_) => GameProvider(),
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

class ShadowBurnApp extends StatelessWidget {
  const ShadowBurnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShadowBurn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00E5FF),
        scaffoldBackgroundColor: Colors.black,
        textTheme: GoogleFonts.rajdhaniTextTheme(Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white)),
      ),
      home: const GameWrapper(), 
    );
  }
}

class GameWrapper extends StatefulWidget {
  const GameWrapper({super.key});
  @override State<GameWrapper> createState() => _GameWrapperState();
}

class _GameWrapperState extends State<GameWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().checkMidnightReset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    if (game.isClassChangeActive) return const ClassChangeQuestScreen(); 
    if (game.isInPenaltyZone) return const PenaltyOverlay();
    if (game.dungeonResult != null) return const DungeonResultOverlay();

    return const MainScaffold();
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});
  @override State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // Contrôleur pour gérer le glissement entre les écrans
  final PageController _pageController = PageController(initialPage: 0);
  int _activePage = 0;

  // Liste épurée : QUÊTE, DONJONS, STATUT
  final List<Widget> _screens = [
    const StatsQuestsScreen(),      // Page 0
    const InventoryDungeonScreen(), // Page 1
    const ProfileScreen(),          // Page 2
  ];

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final Color systemBlue = const Color(0xFF00E5FF);
    
    if (game.activeDungeon != null) {
      return const Stack(children: [InventoryDungeonScreen(), UrgentQuestOverlay()]);
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          // PageView remplace IndexedStack pour permettre le glissement
          body: PageView(
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _activePage = page;
              });
            },
            children: _screens,
          ),
          // Plus de barre de navigation, juste un indicateur discret en bas
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
                    boxShadow: _activePage == index ? [BoxShadow(color: systemBlue, blurRadius: 5)] : [],
                  ),
                );
              }),
            ),
          ),
        ),
        const UrgentQuestOverlay(),
      ],
    );
  }
}