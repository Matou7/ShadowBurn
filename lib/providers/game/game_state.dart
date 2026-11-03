// lib/providers/game/game_state.dart

part of '../game_provider.dart';

abstract class _GameBase extends ChangeNotifier {
  String _username = "Mathis";
  String _rank = "E";
  int _currentHp = 100;
  int _maxHp = 100;
  double _xp = 0;
  int _coins = 0;
  int _totalSurpassement = 0;
  String _equippedTitle = "Nouveau Chasseur";
  List<String> _unlockedTitles = ["Nouveau Chasseur"];

  bool _isPro = false;

  int _pompes = 0;
  int _abdos = 0;
  int _squats = 0;

  double _dailyKm = 0.0;

  int _totalPompes = 0;
  int _totalAbdos = 0;
  int _totalSquats = 0;
  double _totalKm = 0.0;
  int _currentStreak = 0;
  int _dungeonsCompleted = 0;

  int _streak = 0;
  String? _lastResetDateStr;
  int _dailySteps = 0;
  double _sessionKm = 0.0;
  int _dailyCyclesCompleted = 0;
  bool _recordBrokenToday = false;
  bool _isTracking = false;
  bool _isAttacking = false;
  int _stepBufferForXp = 0;
  DateTime? _lastOngoingUpdate;

  int _maxPompes = 0;
  int _maxAbdos = 0;
  int _maxSquats = 0;
  double _maxKm = 0.0;

  bool _isClassChangeStarted = false;
  DateTime? _classChangeEndTime;
  double _classChangeKm = 0.0;
  int _classChangePompes = 0;
  int _classChangeAbdos = 0;
  int _classChangeSquats = 0;

  Map<String, dynamic> _calendarHistory = {};
  List<dynamic> _saveHistory = [];
  Map<String, int> _inventoryKeys = {'E': 0, 'D': 0, 'C': 0, 'B': 0, 'A': 0, 'S': 0, 'NATION': 0};

  bool _isInPenaltyZone = false;
  int _penaltySquatsDone = 0;
  int _kPenaltyGoal = 100;

  Dungeon? _activeDungeon;
  bool _isActiveDungeonRed = false;
  Map<String, dynamic>? _dungeonResult;
  List<Dungeon> _activeThreats = [];

  bool _sandbox = false;
  bool _godModePersistPenalty = false;
  Map<String, dynamic>? _sandboxSnapshot;
  String _adminPassword = "ADMIN";

  bool _loaded = false;
  bool _isSurpassQuest = false;
  bool _showLevelUpOverlay = false;
  String _lastRankUp = "E";
  bool _warningGiven = false;

  final Random _rng = Random();
  final StepService _steps = StepService();
  Timer? _clockTimer;
  Timer? _dungeonTimer;
  Timer? _saveTimer;

  UrgentQuestProvider? _urgent;
  Map<String, dynamic>? _pendingUrgentJson;

  String get username => _username;
  String get rank => _rank;
  int get currentHealth => _currentHp;
  int get maxHealth => _maxHp;
  double get currentXP => _xp;
  int get goldCoins => _coins;
  set goldCoins(int val) {
    _coins = val;
  }

  int get totalSurpassement => _totalSurpassement;
  String get equippedTitle => _equippedTitle;
  List<String> get unlockedTitles => List.unmodifiable(_unlockedTitles);

  bool get isPro => _isPro;

  int get pompes => _pompes;
  int get abdos => _abdos;
  int get squats => _squats;
  int get pompesDone => _pompes;
  int get abdosDone => _abdos;
  int get squatsDone => _squats;

  int get goalPompes => _cfg.goalExo;
  int get goalAbdos => _cfg.goalExo;
  int get goalSquats => _cfg.goalExo;
  int get goalDailyExo => _cfg.goalExo;
  double get goalKm => _cfg.goalKm;

  double get kmCycleCurrent => _dailyKm;
  bool get isTrackingRun => _isTracking;

  int get totalPompes => _totalPompes;
  int get totalAbdos => _totalAbdos;
  int get totalSquats => _totalSquats;
  double get totalKm => _totalKm;
  int get currentStreak => _currentStreak;
  int get dungeonsCompleted => _dungeonsCompleted;

  bool get isClassChangeActive => _isClassChangeStarted;
  bool get isClassChangeStarted => _isClassChangeStarted;
  bool get isClassChangeAvailable => canStartClassChange;
  DateTime? get classChangeEndTime => _classChangeEndTime;
  double get classChangeKm => _classChangeKm;
  int get classChangePompes => _classChangePompes;
  int get classChangeAbdos => _classChangeAbdos;
  int get classChangeSquats => _classChangeSquats;

  double get goalNationKm => 20.0;
  int get goalNationPompes => 200;
  int get goalNationAbdos => 200;
  int get goalNationSquats => 200;

  String get formattedRemainingTime {
    if (_classChangeEndTime == null) return "00:00:00";
    final remaining = _classChangeEndTime!.difference(DateTime.now());
    if (remaining.isNegative) return "00:00:00";
    final h = remaining.inHours.toString().padLeft(2, '0');
    final m = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  Map<String, dynamic> get calendarHistory => Map.unmodifiable(_calendarHistory);
  List<dynamic> get saveHistory => List.unmodifiable(_saveHistory);
  Map<String, int> get inventoryKeys => Map.unmodifiable(_inventoryKeys);

  bool get isInPenaltyZone => _isInPenaltyZone;
  int get penaltySquatsDone => _penaltySquatsDone;
  int get penaltyGoal => _kPenaltyGoal;

  Dungeon? get activeDungeon => _activeDungeon;
  bool get isInDungeon => _activeDungeon != null;
  bool get isDungeonRed => _isActiveDungeonRed;
  Map<String, dynamic>? get dungeonResult => _dungeonResult;
  List<Dungeon> get activeThreats => List.unmodifiable(_activeThreats);

  bool get isGodMode => _sandbox;
  bool get godModePersistPenalty => _godModePersistPenalty;

  bool get isLoaded => _loaded;
  bool get isSurpassQuest => _isSurpassQuest;
  bool get showLevelUpOverlay => _showLevelUpOverlay;
  String get lastRankUp => _lastRankUp;

  int get rankIndex => Balance.order.indexOf(_rank);
  RankConfig get _cfg => Balance.of(_rank);

  double get nextRankThreshold => _cfg.xpNext;
  double get currentRankFloor => _cfg.xpFloor;
  double get vitality => 1.0;
  double get _vitality => 1.0;
  double get goldMultiplier => 1.0;

  int get priceMinorPotion => 50;
  int get priceMajorPotion => 150;
  int get priceFullHeal => 300;

  bool get canStartClassChange =>
      _rank == "S" && _xp >= Balance.classChangeXp && !_isClassChangeStarted;

  UrgentQuestProvider? get urgentQuestProvider => _urgent;
  set urgentQuestProvider(UrgentQuestProvider? provider) {
    _urgent = provider;
  }

  void _notify() => notifyListeners();

  Future<String> _getUniqueHardwareId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? hw = prefs.getString('shadow_hardware_fingerprint');
      if (hw == null || hw.isEmpty) {
        hw = "hw_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(999999)}";
        await prefs.setString('shadow_hardware_fingerprint', hw);
      }
      return hw;
    } catch (_) {
      return "hw_generic_device_${_username.hashCode}";
    }
  }

  void revokePro() {
    _isPro = false;
    _requestSave();
    _notify();
  }

  void updateUsername(String newName) {
    if (newName.trim().isNotEmpty) {
      _username = newName.trim();
      _requestSave();
      _notify();
    }
  }

  void closeResultScreen() {
    _dungeonResult = null;
    _showLevelUpOverlay = false;
    _notify();
  }

  bool buyItem(String id) {
    int price = 0;
    if (id == 'mineure') {
      price = priceMinorPotion;
      if (_coins >= price && _currentHp < _maxHp) {
        _coins -= price;
        _currentHp = (_currentHp + 50).clamp(0, _maxHp);
        _requestSave();
        _notify();
        return true;
      }
    } else if (id == 'majeure') {
      price = priceMajorPotion;
      if (_coins >= price && _currentHp < _maxHp) {
        _coins -= price;
        _currentHp = (_currentHp + 200).clamp(0, _maxHp);
        _requestSave();
        _notify();
        return true;
      }
    } else if (id == 'guérison') {
      price = priceFullHeal;
      if (_coins >= price && _currentHp < _maxHp) {
        _coins -= price;
        _currentHp = _maxHp;
        _requestSave();
        _notify();
        return true;
      }
    }
    return false;
  }

  void equipTitle(String title) {
    if (_unlockedTitles.contains(title)) {
      _equippedTitle = title;
      _requestSave();
      _notify();
    }
  }

  void _checkTitles({bool silent = false}) {
    final stats = TitleStats(
      rankIndex: Balance.order.indexOf(_rank),
      streak: _currentStreak,
      pompes: _totalPompes,
      abdos: _totalAbdos,
      squats: _totalSquats,
      km: _totalKm,
      dungeons: _dungeonsCompleted,
      surpass: _totalSurpassement,
    );

    for (final t in Titles.catalog) {
      if (!_unlockedTitles.contains(t.name) && t.isUnlocked(stats)) {
        _unlockedTitles.add(t.name);
        if (!silent) {
          NotificationService.showNotification(
            "NOUVEAU TITRE DÉBLOQUÉ",
            "Titre acquis : ${t.name}",
            type: 'levelup',
          );
        }
      }
    }
  }

  void _syncStatsToRank() {
    _maxHp = _cfg.maxHp;
    if (_currentHp > _maxHp) _currentHp = _maxHp;
  }

  void _syncTitleWithRank() {
    switch (_rank.toUpperCase()) {
      case "D":
        _equippedTitle = "Lame Naissante";
        break;
      case "C":
        _equippedTitle = "Traqueur d'Élite";
        break;
      case "B":
        _equippedTitle = "Marteau des Donjons";
        break;
      case "A":
        _equippedTitle = "Fléau des Portails";
        break;
      case "S":
        _equippedTitle = "Seigneur de Guerre";
        break;
      case "NATION":
        _equippedTitle = "Autorité Nationale";
        break;
      case "MONARQUE":
        _equippedTitle = "Monarque des Ombres";
        break;
      default:
        _equippedTitle = "Nouveau Chasseur";
    }
    if (!_unlockedTitles.contains(_equippedTitle)) {
      _unlockedTitles.add(_equippedTitle);
    }
  }

  String _todayKey() => DateTime.now().toIso8601String().split('T')[0];
  DateTime? _parseDay(String s) => DateTime.tryParse(s);

  void _requestSave();
  Future<void> _saveNow();
  void _applyJson(Map<String, dynamic> json);
  Map<String, dynamic> _toJson();
  void _onSteps(StepEvent e);
  void _updateCalendarActivity();
  void _syncCycleWithCalendar();
  Future<void> checkMidnightReset();
  void _updateOngoingSystem({bool force = false});
  void _loseXp(num amount);
  void _checkRankUp();
  void _rewardUrgentQuest();
  void _startDungeonTimer();
  void _checkDungeonStatus();
  void _checkCycleCompletion();
  void debugTriggerRankedQuest();
  void debugForceSpawnThreat({bool isRed = false});
  void processPenaltySquats(int count);
  void triggerDailyPenalty();
  void toggleRunTracking();
  void addReps(String type, int count);
  void incrementExercise(String type);
  void trainAllManualExercises();
  void enterDungeon(String k, {bool isThreat = false, Dungeon? threatInstance, bool isRed = false});
}