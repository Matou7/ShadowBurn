import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedometer/pedometer.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';

import 'urgent_quest_provider.dart';
import '../models/dungeon.dart';
import '../data/dungeon_database.dart';
import '../services/notification_service.dart';
import '../services/audio_service.dart';

// --- PROVIDER PRINCIPAL ---
class GameProvider extends ChangeNotifier with WidgetsBindingObserver {
  UrgentQuestProvider? _urgentQuestProvider;
  final Random _rng = Random();
  
  Timer? _dungeonTimer;
  Timer? _midnightTimer;
  StreamSubscription<StepCount>? _stepSubscription;

  // --- SECTION ADMIN & GOD MODE ---
  bool _isAdminMode = false;
  
  // Getters pour l'accès extérieur
  bool get isAdminMode => _isAdminMode;
  bool get isGodMode => _isAdminMode; 
  
  // VARIABLE MODIFIABLE
  String _adminPassword = "SOLO"; 

  // Active/Désactive le mode admin via mot de passe
  bool toggleAdminMode(String password) {
    if (password == _adminPassword) {
      _isAdminMode = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  // Méthode pour définir directement le mode
  void setGodMode(bool value) {
    _isAdminMode = value;
    notifyListeners();
  }

  void disableAdminMode() {
    _isAdminMode = false;
    notifyListeners();
  }

  // Changer le mot de passe dynamiquement
  void setAdminPassword(String newPassword) {
    _adminPassword = newPassword;
    _saveData(); 
    notifyListeners();
  }

  // Setters Admin (Accepte les virgules pour les KM)
  void setDailyStat(String type, num value) {
    if (type == 'pompes') _pompes = value.toInt();
    if (type == 'abdos') _abdos = value.toInt();
    if (type == 'squats') _squats = value.toInt();
    
    // GESTION COURSE (KM)
    if (type == 'course') {
       _sessionKm = value.toDouble();
    }

    _checkDailyCycle(); 
    notifyListeners();
    _saveData();
  }

  // Permet de DÉFINIR le nombre exact de clés
  void setDungeonKey(String rank, int quantity) {
    _inventoryKeys[rank] = quantity;
    notifyListeners();
    _saveData();
  }
  // --- FIN SECTION ADMIN ---

  // --- OBJECTIFS FINAUX (NATION) ---
  int get goalNationPompes => 200;
  int get goalNationAbdos  => 200;
  int get goalNationSquats => 200;
  double get goalNationKm  => 20.0;

  String _username = "Chasseur"; 
  
  double _xp = 0; 
  int _currentHp = 100;
  int _maxHp = 100;
  int _coins = 0; 
  String _rank = "E";
  int _strength = 10;
  int _endurance = 10;
  
  // --- STATS QUOTIDIENNES ---
  int _pompes = 0;
  int _abdos = 0;
  int _squats = 0;
  int _streak = 0;
  int _dailySteps = 0;
  double _sessionKm = 0.0;

  // --- STATS CUMULÉES ---
  int _totalPompes = 0;
  int _totalAbdos = 0;
  int _totalSquats = 0;
  double _totalKm = 0.0;
  int _currentStreak = 0; 

  int _totalSurpassement = 0;

  // --- RECORDS (PR) ---
  int _maxPompes = 0;
  int _maxAbdos = 0;
  int _maxSquats = 0;
  double _maxKm = 0.0;
  bool _recordBrokenToday = false; 

  int get maxPompes => _maxPompes;
  int get maxAbdos => _maxAbdos;
  int get maxSquats => _maxSquats;
  double get maxKm => _maxKm;

  int get totalPompes => _totalPompes;
  int get totalAbdos => _totalAbdos;
  int get totalSquats => _totalSquats;
  double get totalKm => _totalKm;
  int get currentStreak => _streak; 
  int get totalSurpassement => _totalSurpassement;

  // --- CYCLES ---
  int _dailyCyclesCompleted = 0;
  double _kmConsumedByDaily = 0.0;
  int get dailyCyclesCompleted => _dailyCyclesCompleted;

  bool _isInPenaltyZone = false;
  int _penaltySquatsDone = 0;
  static const int PENALTY_GOAL = 100;

  int _dungeonsCompleted = 0;

  bool _showLevelUpOverlay = false;
  String _lastRankUp = "E";

  Map<String, int> _inventoryKeys = {"E": 0, "D": 0, "C": 0, "B": 0, "A": 0, "S": 0, "NATION": 0};
  List<String> _unlockedTitles = ["Nouveau Chasseur"];
  String _equippedTitle = "Nouveau Chasseur";

  // --- HISTORIQUE ---
  List<Map<String, dynamic>> _saveHistory = [];
  List<Map<String, dynamic>> get saveHistory => _saveHistory;

  Map<String, dynamic> _calendarHistory = {};
  Map<String, dynamic> get calendarHistory => _calendarHistory;
  
  Dungeon? _activeDungeon;
  List<Dungeon> _activeThreats = [];
  Map<String, dynamic>? _dungeonResult;
  bool _isTracking = false;
  String? _lastResetDateStr;
  bool _isAttacking = false;
  int _initialStepsAtStart = -1;
  int _stepBufferForXp = 0;
  bool _isActiveDungeonRed = false;

  bool _isSurpassQuest = false; 

  // --- CHANGEMENT DE CLASSE ---
  double _classChangeKm = 0.0;
  int _classChangePompes = 0;
  int _classChangeAbdos = 0;
  int _classChangeSquats = 0;
  
  DateTime? _classChangeEndTime; 
  bool _isClassChangeStarted = false; 

  // --- GETTERS PHYSIQUES ---
  double get goalKm {
    switch(_rank) {
        case 'E': return 1.0;
        case 'D': return 1.5;
        case 'C': return 2.0;
        case 'B': return 3.0;
        case 'A': return 5.0;
        case 'S': return 10.0;
        case 'NATION': return 20.0;
        default: return 1.0;
    }
  }
  
  int get goalDailyExo {
    switch(_rank) {
        case 'E': return 10;
        case 'D': return 20;
        case 'C': return 40;
        case 'B': return 60;
        case 'A': return 80;
        case 'S': return 100;
        case 'NATION': return 200;
        default: return 10;
    }
  }

  int get goalDungeonExo => goalDailyExo + 10;
  int get goalPompes => goalDailyExo;
  int get goalAbdos => goalDailyExo;
  int get goalSquats => goalDailyExo;

  String get username => _username;
  double get currentXP => _xp;
  int get goldCoins => _coins; 
  String get rank => _rank;
  int get currentHealth => _currentHp;
  int get maxHealth => _maxHp;
  int get strength => _strength;
  int get endurance => _endurance;
  int get pompesDone => _pompes;
  int get abdosDone => _abdos;
  int get squatsDone => _squats;
  int get streakDays => _streak;
  int get steps => _dailySteps;
  
  double get kmCycleCurrent => (_sessionKm - _kmConsumedByDaily).clamp(0.0, 9999.0);
  double get km => _sessionKm;

  Dungeon? get activeDungeon => _activeDungeon;
  bool get isInDungeon => _activeDungeon != null;
  List<Dungeon> get activeThreats => _activeThreats;
  Map<String, int> get inventoryKeys => _inventoryKeys;
  bool get isInPenaltyZone => _isInPenaltyZone;
  int get penaltySquatsDone => _penaltySquatsDone;
  String get equippedTitle => _equippedTitle;
  List<String> get unlockedTitles => _unlockedTitles;
  
  Map<String, dynamic>? get dungeonResult => _dungeonResult;
  bool get isTrackingRun => _isTracking;
  bool get isAttacking => _isAttacking;
  bool get isActiveDungeonRed => _isActiveDungeonRed;
  int get dungeonsCompleted => _dungeonsCompleted;
  
  bool get showLevelUpOverlay => _showLevelUpOverlay;
  String get lastRankUp => _lastRankUp;

  double get classChangeKm => _classChangeKm;
  int get classChangePompes => _classChangePompes;
  int get classChangeAbdos => _classChangeAbdos;
  int get classChangeSquats => _classChangeSquats;
  
  bool get isClassChangeStarted => _isClassChangeStarted;
  bool get isClassChangeActive => _isClassChangeStarted; 
  // SEUIL MODIFIÉ : 7.5 Milliards pour le déclenchement
  bool get isClassChangeAvailable => _rank == "S" && _xp >= 7500000000 && !_isClassChangeStarted; 
  bool get hasQuestFailed => _isClassChangeStarted && formattedRemainingTime == "00:00:00" && _currentHp == 1;

  double get forceProgress => ((_pompes/max(1, goalPompes) + _abdos/max(1, goalAbdos) + _squats/max(1, goalSquats)) / 3).clamp(0.0, 1.0);
  double get enduranceProgress => (kmCycleCurrent / max(0.1, goalKm)).clamp(0.0, 1.0);
  
  String get formattedRemainingTime {
    if (_classChangeEndTime == null) return "00:00:00";
    final now = DateTime.now();
    if (now.isAfter(_classChangeEndTime!)) return "00:00:00";
    final diff = _classChangeEndTime!.difference(now);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(diff.inHours)}:${twoDigits(diff.inMinutes.remainder(60))}:${twoDigits(diff.inSeconds.remainder(60))}";
  }

  String formatFullNumber(double number) {
    return number.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }

  String formatNumber(double number) {
    if (number >= 1000000000) return "${(number / 1000000000).toStringAsFixed(1)} Mrd";
    if (number >= 1000000) return "${(number / 1000000).toStringAsFixed(1)} M";
    if (number >= 1000) return "${(number / 1000).toStringAsFixed(1)} K";
    return number.toInt().toString();
  }

  // --- SEUILS D'XP (ÉQUILIBRÉS 2 ANS) ---
  double get nextRankThreshold {
    switch (_rank) {
      case "E": return 1000000;             
      case "D": return 5000000;             
      case "C": return 20000000;             
      case "B": return 50000000;             
      case "A": return 100000000;             
      case "S": return 7500000000; // 7.5 Milliards
      case "NATION": return 7500000000; 
      default: return 1000000;
    }
  }
  
  String get xpDisplayString {
    if (_rank == "NATION") return "${formatNumber(_xp)} XP (MAX)";
    return "${formatNumber(_xp)} / ${formatNumber(nextRankThreshold)} XP";
  }
  
  double get currentRankFloor {
     switch (_rank) {
      case "E": return 0;
      case "D": return 1000001;
      case "C": return 5000001;
      case "B": return 20000001;
      case "A": return 50000001;
      case "S": return 100000001;
      case "NATION": return 7500000001;
      default: return 0;
    }
  }
  
  double get xpInCurrentRank => (_xp - currentRankFloor).clamp(0, 7500000000); 
  double get rankRangeTotal => (nextRankThreshold - currentRankFloor) > 0 ? nextRankThreshold - currentRankFloor : 1;
  double get xpProgress => _rank == "NATION" ? 1.0 : (xpInCurrentRank / rankRangeTotal).clamp(0.0, 1.0);

  int get rankIndex => ["E", "D", "C", "B", "A", "S", "NATION"].indexOf(_rank);
  int get xpMultiplier => _rank == "NATION" ? 100 : 1; 
  int get goldMultiplier => (20 * pow(1.8, rankIndex)).toInt();
  int get shopPriceMultiplier => (1 * pow(1.8, rankIndex)).toInt();
  int get priceMinorPotion => 200 * shopPriceMultiplier;
  int get priceMajorPotion => 1000 * shopPriceMultiplier;
  int get priceFullHeal => 5000 * shopPriceMultiplier;

  void _checkRankUp() {
    if (_rank == "NATION") return; 
    const ranks = ["E", "D", "C", "B", "A", "S", "NATION"];
    int currentIdx = ranks.indexOf(_rank);
    if (currentIdx < ranks.length - 1) {
       String nextRank = ranks[currentIdx + 1];
       if (nextRank == "NATION") return; 
       if (_xp >= nextRankThreshold) {
           _rank = nextRank;
           _syncStatsToRank(); 
           _currentHp = _maxHp;
           _lastRankUp = _rank;
           _showLevelUpOverlay = true;
           Vibration.vibrate(duration: 500); 
           AudioService.playLevelUp(); // SON LEVEL UP
           // --- NOTIFICATION PERSONNALISÉE ---
           NotificationService.showNotification("LEVEL UP!", "Félicitations $_username ! Vous êtes passé au rang $_rank !", type: 'levelup');
           notifyListeners();
           _saveData();
       }
    }
  }
  
  void closeLevelUpOverlay() { _showLevelUpOverlay = false; notifyListeners(); }

  void _syncStatsToRank() {
    _maxHp = _getMaxHpForRank(_rank);
    if (_currentHp > _maxHp) _currentHp = _maxHp;
    switch (_rank) {
      case "NATION": _strength = 1000; _endurance = 1000; break;
      case "S": _strength = 500; _endurance = 500; break;
      case "A": _strength = 250; _endurance = 250; break;
      case "B": _strength = 150; _endurance = 150; break;
      case "C": _strength = 80; _endurance = 80; break;
      case "D": _strength = 40; _endurance = 40; break;
      default: _strength = 10; _endurance = 10; break;
    }
  }

  // --- LOGIQUE COULEUR DYNAMIQUE (RANG) ---
  Color _getRankColor() {
    switch(_rank) {
      case 'E': return const Color(0xFFB0BEC5); // Gris Acier
      case 'D': return const Color(0xFF4CAF50); // Vert
      case 'C': return const Color(0xFF2196F3); // Bleu
      case 'B': return const Color(0xFF9C27B0); // Violet
      case 'A': return const Color(0xFFF44336); // Rouge
      case 'S': return const Color(0xFFFFD700); // Or
      case 'NATION': return const Color(0xFF00E5FF); // Cyan Néon
      default: return const Color(0xFFB0BEC5);
    }
  }

  // --- MISE A JOUR NOTIFICATION SYSTÈME ---
  void _updateOngoingSystem() {
    String targetRank = "NATION"; // Valeur par défaut
    
    // Calcul du prochain rang
    const ranks = ["E", "D", "C", "B", "A", "S", "NATION"];
    int idx = ranks.indexOf(_rank);
    if (idx < ranks.length - 1) targetRank = ranks[idx + 1];

    // TITRE (Ce qui apparaît en gros) : Le message de motivation
    String title = "Le rang $targetRank t'attend.";
    String body = "";
    
    // Calcul du pourcentage global
    double p = (_pompes / max(1, goalDailyExo)).clamp(0.0, 1.0);
    double a = (_abdos / max(1, goalDailyExo)).clamp(0.0, 1.0);
    double s = (_squats / max(1, goalDailyExo)).clamp(0.0, 1.0);
    double k = (kmCycleCurrent / max(0.1, goalKm)).clamp(0.0, 1.0);
    
    int totalProgress = ((p + a + s + k) / 4 * 100).toInt();

    // Appel au service
    NotificationService.showForegroundServiceNotification(
      title, 
      body, 
      color: _getRankColor(),
      progress: totalProgress,
      maxProgress: 100
    );
  }

  // --- DEMANDE DE PERMISSIONS ---
  Future<void> _requestPermissions() async {
    if (await Permission.activityRecognition.isDenied) {
        await Permission.activityRecognition.request();
    }
    if (await Permission.notification.isDenied) {
        await Permission.notification.request();
    }
  }

  String _getTodayKey() {
    return DateTime.now().toIso8601String().split('T')[0];
  }

  // --- LOGIQUE DE SYNCHRONISATION CYCLE-CALENDRIER ---
  void _syncCycleWithCalendar() {
    String today = _getTodayKey();
    if (_calendarHistory[today]?['status'] == 'gold') {
      if (_dailyCyclesCompleted == 0) {
        _dailyCyclesCompleted = 1;
        print("--- 🛡️ SYNCHRO : Calendrier OR détecté -> Cycle forcé à 1 (0 XP) ---");
        _saveData();
      }
    }
  }

  void _updateCalendarActivity() {
    String today = _getTodayKey();
    
    if (_calendarHistory[today]?['status'] == 'gold') {
        return;
    }

    bool kmOk = kmCycleCurrent >= goalKm;
    bool pompesOk = _pompes >= goalDailyExo;
    bool abdosOk = _abdos >= goalDailyExo;
    bool squatsOk = _squats >= goalDailyExo;

    bool isOneGoalMet = kmOk || pompesOk || abdosOk || squatsOk;
    bool isAllFinished = kmOk && pompesOk && abdosOk && squatsOk;

    if (isAllFinished) {
       _calendarHistory[today] = {'status': 'gold', 'recordBroken': _recordBrokenToday};
       if (_dailyCyclesCompleted == 0) {
           _dailyCyclesCompleted = 1;
       }
    }
    else if (isOneGoalMet) {
      _calendarHistory[today] = {'status': 'blue', 'recordBroken': false};
    } else {
      if (_calendarHistory[today] == null || _calendarHistory[today]?['status'] != 'grey') {
          _calendarHistory[today] = {'status': 'grey', 'recordBroken': false};
      }
    }
  }

  // --- LOGIQUE DE RESET TEMPOREL & CALENDRIER ---
  void checkMidnightReset() async { 
    final now = DateTime.now(); 
    final currentDateStr = _getTodayKey(); 
    
    if (_lastResetDateStr == null) {
        _lastResetDateStr = currentDateStr;
        _inventoryKeys[_rank] = (_inventoryKeys[_rank] ?? 0) + 1;
        await _saveData();
        _updateOngoingSystem(); // Init notif
        return;
    }

    if (_lastResetDateStr != currentDateStr) { 
        DateTime lastDate = DateTime.parse(_lastResetDateStr!);
        DateTime today = DateTime.parse(currentDateStr);
        int daysMissed = today.difference(lastDate).inDays;

        for (int i = 0; i < daysMissed; i++) {
            bool cycleDoneThisDay = (i == 0) ? (_dailyCyclesCompleted > 0) : false;
            
            // --- PÉNALITÉ (Fixe par rang, ~2 jours) ---
            if (!cycleDoneThisDay && _rank != "NATION") {
                _streak = 0; 
                double penalty = 2000; // Base E
                switch(_rank) {
                    case 'E': penalty = 2000; break;
                    case 'D': penalty = 5000; break;
                    case 'C': penalty = 15000; break;
                    case 'B': penalty = 40000; break;
                    case 'A': penalty = 100000; break;
                    case 'S': penalty = 20000000; break; // 20M = ~2 jours grind
                }
                _xp = (_xp - penalty).clamp(currentRankFloor, 7500000000);
                _isInPenaltyZone = true; 
                _penaltySquatsDone = 0;
            }

            String dateKey = lastDate.add(Duration(days: i)).toIso8601String().split('T')[0];
            if (_calendarHistory[dateKey] == null) {
                _calendarHistory[dateKey] = {'status': 'grey', 'recordBroken': false};
            }
            if (cycleDoneThisDay) {
                _calendarHistory[dateKey] = {'status': 'gold', 'recordBroken': (i == 0) ? _recordBrokenToday : false};
            }

            _inventoryKeys[_rank] = (_inventoryKeys[_rank] ?? 0) + 1;

            if (i == 0) {
               _pompes = 0; _abdos = 0; _squats = 0; 
               _dailySteps = 0; 
               _dailyCyclesCompleted = 0;
               _recordBrokenToday = false; 
            }
        }

        if (daysMissed > 1) {
             NotificationService.showNotification("RÉVEIL TARDIF", "Vous avez manqué $daysMissed jours. Sanctions appliquées.", type: 'penalty');
        } else {
             print("--- 📅 NOUVEAU JOUR : CLÉ $_rank AJOUTÉE ---");
        }

        _lastResetDateStr = currentDateStr; 
        
        if (kmCycleCurrent >= goalKm) {
           _calendarHistory[currentDateStr] = {'status': 'blue', 'recordBroken': false};
        } else {
           _calendarHistory[currentDateStr] = {'status': 'grey', 'recordBroken': false};
        }
        
        await _saveData(); 
        _updateOngoingSystem(); 
        notifyListeners(); 
    } 
  }

  void incrementExercise(String type) {
    checkMidnightReset(); 
    _isAttacking = true;

    notifyListeners(); 
    bool handled = false;
    
    // --- GESTION QUÊTE URGENTE / SURPASSEMENT ---
    if (_urgentQuestProvider != null && _urgentQuestProvider!.isActive) {
        if (_urgentQuestProvider!.type.toLowerCase().contains(type.toLowerCase())) {
            _urgentQuestProvider!.addProgress(5, type);
            if (_urgentQuestProvider!.isCompleted) {
                _rewardUrgentQuest();
                handled = true; 
                Future.delayed(const Duration(milliseconds: 150), () { _isAttacking = false; notifyListeners(); });
                return; 
            }
            handled = true;
        }
    }
    
    if (_isClassChangeStarted) {
      if (formattedRemainingTime != "00:00:00") {
          if (type.toLowerCase().contains("pompes")) {
              if (_classChangePompes < goalNationPompes) _classChangePompes += 5;
          }
          else if (type.toLowerCase().contains("abdos")) {
              if (_classChangeAbdos < goalNationAbdos) _classChangeAbdos += 5;
          }
          else if (type.toLowerCase().contains("squats")) {
              if (_classChangeSquats < goalNationSquats) _classChangeSquats += 5;
          }
          _saveData();
          handled = true; 
      }
    }
    else if (_isInPenaltyZone) {
      if (type.toLowerCase().contains("squats")) {
        _penaltySquatsDone += 5; 
        if (_penaltySquatsDone >= PENALTY_GOAL) { 
            _isInPenaltyZone = false; _penaltySquatsDone = 0; _saveData(); 
        }
      }
      handled = true;
    }
    else if (_activeDungeon != null) {
          bool dungeonUpdated = false;
          for (int i = 0; i < _activeDungeon!.tasks.length; i++) {
             if (_activeDungeon!.tasks[i]['type'].toString().toUpperCase() == type.toUpperCase()) {
                 _activeDungeon!.progress[i] += 5;
                 dungeonUpdated = true;
             }
          }
          if (dungeonUpdated) {
              _checkDungeonStatus();
              handled = true; 
          }
    }
    
    if (!handled) {
          if (type.toLowerCase().contains("pompes")) {
              _pompes += 5;
              _totalPompes += 5; 
              if (_pompes > _maxPompes) { _maxPompes = _pompes; _recordBrokenToday = true; }
          }
          else if (type.toLowerCase().contains("abdos")) {
              _abdos += 5;
              _totalAbdos += 5; 
              if (_abdos > _maxAbdos) { _maxAbdos = _abdos; _recordBrokenToday = true; }
          }
          else if (type.toLowerCase().contains("squats")) {
              _squats += 5;
              _totalSquats += 5; 
              if (_squats > _maxSquats) { _maxSquats = _squats; _recordBrokenToday = true; }
          }
          
          double bonus = (_currentHp >= _maxHp * 0.8) ? 1.2 : 1.0;
          _xp += (5 * bonus); 

          _checkDailyCycle(); 
    }
    
    _updateCalendarActivity();
    _updateOngoingSystem(); 
    _checkRankUp(); _saveData(); 
    
    Future.delayed(const Duration(milliseconds: 150), () { _isAttacking = false; notifyListeners(); });
  }

  void _checkDailyCycle() { 
    bool cycleValidated = false;
    
    while (kmCycleCurrent >= goalKm && _pompes >= goalDailyExo && _abdos >= goalDailyExo && _squats >= goalDailyExo) {
       
       _dailyCyclesCompleted++; 
       
       if (_dailyCyclesCompleted > 1) {
           _totalSurpassement++; 
       }
       
       int baseReward = 0;
       switch(_rank) {
           case 'E': baseReward = 600; break;
           case 'D': baseReward = 1200; break;
           case 'C': baseReward = 3000; break;
           case 'B': baseReward = 8000; break;
           case 'A': baseReward = 15000; break;
           case 'S': baseReward = 30000; break;
           case 'NATION': baseReward = 100000; break;
           default: baseReward = 600;
       }
       
       double surpassementMult = 1.0;
       if (_dailyCyclesCompleted == 2) {
           surpassementMult = 1.5; 
           _isSurpassQuest = true; 
           debugTriggerRankedQuest(); 
           // --- NOTIF PERSONNALISÉE ---
           NotificationService.showNotification("SURPASSEMENT", "$_username, 2ème cycle validé ! Quête Urgente détectée.", type: 'urgent');
       } else if (_dailyCyclesCompleted >= 3) {
           surpassementMult = 2.0; 
           addKey(_rank, 1); 
           // --- NOTIF PERSONNALISÉE ---
           NotificationService.showNotification("LIMITE DÉPASSÉE", "$_username, vous êtes un acharné ! Clé obtenue.", type: 'levelup');
       }

       double multiplier = (_currentHp >= _maxHp * 0.8) ? 1.2 : 1.0;
       int finalXp = (baseReward * multiplier * surpassementMult).toInt();
       
       _xp += finalXp; 
       _streak++; 
       _kmConsumedByDaily += goalKm; 
       
       String today = _getTodayKey();
       _calendarHistory[today] = {'status': 'gold', 'recordBroken': _recordBrokenToday};

       _pompes = 0; _abdos = 0; _squats = 0; 
       cycleValidated = true;
    }
    
    if (cycleValidated) {
       Vibration.vibrate(duration: 200);
       AudioService.playVictory(); 
       
       if (_dailyCyclesCompleted == 1) {
          NotificationService.showNotification("CYCLE VALIDÉ", "Quête Quotidienne accomplie ! XP reçue.", type: 'trophy');
       }
       
       _checkRankUp(); _saveData();
       _updateOngoingSystem(); 
       notifyListeners();
    }
  }

  void _rewardUrgentQuest() {
    if (_urgentQuestProvider == null) return;
    
    if (_isSurpassQuest) {
        // --- NOTIF PERSONNALISÉE ---
        NotificationService.showNotification("SURPASSEMENT RÉUSSI", "Bien joué $_username. Vous avez survécu à la pression.", type: 'levelup');
        AudioService.playVictory(); 
        _urgentQuestProvider!.resetStatus(); 
        _isSurpassQuest = false; 
        _saveData(); 
        notifyListeners();
        return; 
    }

    int baseXP = 100;
    switch(_rank) {
       case 'E': baseXP = 100; break;
       case 'D': baseXP = 300; break;
       case 'C': baseXP = 800; break;
       case 'B': baseXP = 2000; break;
       case 'A': baseXP = 5000; break;
       case 'S': baseXP = 10000; break;
       case 'NATION': baseXP = 20000; break;
    }
    
    double multiplier = (_currentHp >= _maxHp * 0.8) ? 1.2 : 1.0;
    int finalXp = (baseXP * multiplier).toInt();
    if (multiplier > 1.0) print("✨ QUÊTE RÉUSSIE : Bonus vitalité +20% XP !");

    _xp += finalXp; 
    _coins += (20 * goldMultiplier);
    
    _dungeonResult = {'status': 'VICTOIRE', 'xp': finalXp};
    AudioService.playVictory(); 
    _urgentQuestProvider!.resetStatus(); 
    _checkRankUp(); _saveData(); notifyListeners();
  }

  // --- CORRECTION MAJEURE : PÉNALITÉS ÉQUILIBRÉES ---
  void fleeUrgentQuest({bool isTimeout = false}) {
    if (_urgentQuestProvider != null && _urgentQuestProvider!.isActive) {
      
      double penalty = 300; // Par défaut E
      switch(_rank) {
          case 'E': penalty = 500; break;
          case 'D': penalty = 1000; break;
          case 'C': penalty = 5000; break;
          case 'B': penalty = 20000; break;
          case 'A': penalty = 50000; break;
          case 'S': penalty = 200000; break; 
          case 'NATION': penalty = 1000000; break;
      }

      _xp = (_xp - penalty).clamp(currentRankFloor, 7500000000);
      _currentHp = (_currentHp - 20).clamp(0, _maxHp);
      
      String raison = isTimeout ? 'TEMPS ÉCOULÉ' : 'FUITE URGENTE';
      print("--- PÉNALITÉ : -$penalty XP et -20 HP ($raison) ---");
      
      _dungeonResult = {'status': raison, 'xp': -penalty.toInt()};
      AudioService.playDefeat(); // SON DEFAITE
      _urgentQuestProvider!.fail(); 
      if (_isSurpassQuest) _isSurpassQuest = false; 
      notifyListeners(); 
      _saveData();
    }
  }

  void _finishDungeon({required bool victory}) async { 
    if (victory && _activeDungeon != null) { 
      _dungeonsCompleted++; 
      int baseXP = 0;
      switch(_activeDungeon!.rank) {
           case 'E': baseXP = 900; break;
           case 'D': baseXP = 2500; break;
           case 'C': baseXP = 10000; break;
           case 'B': baseXP = 50000; break;
           case 'A': baseXP = 200000; break;
           case 'S': baseXP = 2500000; break; 
           case 'NATION': baseXP = 10000000; break;
           default: baseXP = 900;
      }
      if (_isActiveDungeonRed) baseXP *= 2;
      
      double multiplier = (_currentHp >= _maxHp * 0.8) ? 1.2 : 1.0;
      int finalXp = (baseXP * multiplier).toInt();
      if (multiplier > 1.0) print("✨ VICTOIRE ÉPIQUE : Bonus vitalité +20% XP !");

      int goldReward = (100 * pow(1.5, rankIndex)).toInt();
      _xp += finalXp; 
      _coins += goldReward; 
      
      String lootMsg = "";
      int dropChance = _isActiveDungeonRed ? 30 : 15;
      if (_rng.nextInt(100) < dropChance) {
          List<String> r = ['E', 'D', 'C', 'B', 'A', 'S', 'NATION'];
          int idx = r.indexOf(_activeDungeon!.rank);
          if (idx < r.length - 1) {
              String keyLooted = r[idx + 1];
              addKey(keyLooted, 1);
              lootMsg = "\nLOOT RARE : CLÉ RANG $keyLooted";
              if (await Vibration.hasVibrator() ?? false) { Vibration.vibrate(pattern: [0, 100, 50, 100, 50, 200]); }
          }
      }
      _dungeonResult = {'status': 'VICTOIRE$lootMsg', 'xp': finalXp}; 
      AudioService.playVictory(); // SON VICTOIRE
      _checkRankUp(); 
    } 
    _activeDungeon = null; _isActiveDungeonRed = false; _dungeonTimer?.cancel(); notifyListeners(); _saveData(); 
  }

  int _getRankValue(String r) {
    switch (r) {
      case 'E': return 1; case 'D': return 2; case 'C': return 3; case 'B': return 4;
      case 'A': return 5; case 'S': return 6; case 'NATION': return 10; default: return 1;
    }
  }

  // --- CORRECTION : PÉNALITÉ DONJON ÉQUILIBRÉE (1.5x GAIN) ---
  void leaveDungeon({bool timeout = false}) { 
    if (_activeDungeon != null) {
      double penalty = 1500; // Base E (Gain 900 -> Perte 1500)
      switch(_activeDungeon!.rank) {
          case 'E': penalty = 1500; break;
          case 'D': penalty = 4000; break;
          case 'C': penalty = 15000; break;
          case 'B': penalty = 75000; break;
          case 'A': penalty = 300000; break;
          case 'S': penalty = 4000000; break; // 4 Millions (vs 2.5M gain)
          case 'NATION': penalty = 15000000; break;
      }
      
      _xp = (_xp - penalty).clamp(currentRankFloor, 7500000000);
      _currentHp = (_currentHp ~/ 2).toInt();
      
      String msg = timeout ? 'TEMPS ÉCOULÉ' : 'FUITE HONTEUSE';
      _dungeonResult = {'status': msg, 'xp': -penalty.toInt()}; 
      AudioService.playDefeat(); // SON DEFAITE
    }
    _activeDungeon = null; _isActiveDungeonRed = false; _dungeonTimer?.cancel(); notifyListeners(); _saveData();
  }

  void enterDungeon(String k, {bool isThreat = false, Dungeon? threatInstance, bool isRed = false}) {
    if (_activeDungeon != null) return;
    _isActiveDungeonRed = isRed;
    final d = DungeonDatabase.generateDungeonData(k);
    List<Map<String, dynamic>> tasks = [];
    int targetReps = 0;
    switch(k) {
        case 'E': targetReps = 20; break; case 'D': targetReps = 30; break;
        case 'C': targetReps = 50; break; case 'B': targetReps = 70; break;
        case 'A': targetReps = 90; break; case 'S': targetReps = 110; break;
        case 'NATION': targetReps = 210; break; default: targetReps = 20;
    }
    if (isRed) targetReps = (targetReps * 1.5).toInt();

    tasks.add({'type': 'Pompes', 'amount': targetReps, 'title': 'Pompes'});
    tasks.add({'type': 'Squats', 'amount': targetReps, 'title': 'Squats'});
    tasks.add({'type': 'Abdos', 'amount': targetReps, 'title': 'Abdos'});
    
    _activeDungeon = Dungeon(
        id: isThreat ? threatInstance!.id : DateTime.now().millisecondsSinceEpoch.toString(), 
        rank: k, tasks: tasks, progress: List.filled(tasks.length, 0.0), 
        expiresAt: DateTime.now().add(d['duration']), xpReward: 0, penaltyXp: 0, isRandomThreat: isThreat
    );
    if (!isThreat) addKey(k, -1);
    
    // Suppression des menaces actives si on en lance une
    if (isThreat && threatInstance != null) {
      _activeThreats.removeWhere((t) => t.id == threatInstance.id);
    }

    notifyListeners(); 
    _dungeonTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDungeon == null) timer.cancel();
      else if (DateTime.now().isAfter(_activeDungeon!.expiresAt)) leaveDungeon(timeout: true); 
      else notifyListeners();
    });
  }

  void _checkDungeonStatus() {
      if (_activeDungeon == null) return;
      bool allDone = true;
      for(int i=0; i<_activeDungeon!.tasks.length; i++) {
         if (_activeDungeon!.progress[i] < (_activeDungeon!.tasks[i]['amount'] as num)) allDone = false;
      }
      if (allDone) _finishDungeon(victory: true);
  }

  void _startSensorInternal() { 
    Pedometer.stepCountStream.listen((e) { 
      if (_initialStepsAtStart == -1) _initialStepsAtStart = e.steps; 
      int diff = e.steps - _initialStepsAtStart; 
      if (diff > 0) { 
        _initialStepsAtStart = e.steps; 
        print("Pas détecté... (+${diff} pas)"); 

        checkMidnightReset(); // Vérif Journée
        _updateCalendarActivity(); // MAJ Couleur

        if (_rng.nextInt(3000) == 0 && _activeDungeon == null && !(_urgentQuestProvider?.isActive ?? false)) {
            int roll = _rng.nextInt(100);
            if (roll < 50) debugTriggerRankedQuest(); 
            else if (roll < 90) debugForceSpawnThreat(isRed: false); 
            else debugForceSpawnThreat(isRed: true); 
        }

        double kmAdded = (diff * 0.75 / 1000);
        bool handled = false;
        
        if (_isClassChangeStarted) {
            if (formattedRemainingTime != "00:00:00") {
                 _classChangeKm = (_classChangeKm + kmAdded);
                 if (_classChangeKm > goalNationKm) _classChangeKm = goalNationKm;
                 _saveData();
                 handled = true; 
            }
        } 
        else if (_urgentQuestProvider?.isActive ?? false) {
           _urgentQuestProvider!.addProgress(diff.toDouble(), "PAS"); 
           _urgentQuestProvider!.addProgress(kmAdded, "KM");
           handled = true;
        } 

        if (!handled) { 
            _dailySteps += diff; 
            if (_isTracking) { 
              _sessionKm += kmAdded;
              _totalKm += kmAdded; // CUMUL
              _checkDailyCycle(); 
            }
            _stepBufferForXp += diff;
            if (_stepBufferForXp >= 20) { 
              // --- BONUS VITALITÉ MARCHE ---
              double multiplier = (_currentHp >= _maxHp * 0.8) ? 1.2 : 1.0;
              _xp += (_stepBufferForXp * multiplier); 
              _stepBufferForXp = 0; 
            }
            
            // CHECK RECORD KM
            double currentKmDaily = _dailySteps * 0.75 / 1000;
            if (currentKmDaily > _maxKm) {
                _maxKm = currentKmDaily;
                _recordBrokenToday = true;
            }
        }
        
        _updateOngoingSystem(); // UPDATE LIVE NOTIF SUR CHAQUE PAS
        _checkRankUp(); _saveData(); notifyListeners(); 
      } 
    }); 
  }

void debugForceSpawnThreat({bool isRed = false}) async {
    Dungeon d = Dungeon(
        id: 'debug_${DateTime.now()}', 
        rank: _rank, 
        tasks: [], 
        progress: [], 
        expiresAt: DateTime.now().add(const Duration(minutes: 10)), 
        xpReward: 0, 
        penaltyXp: 0, 
        isRandomThreat: true
    );
    
    String title = isRed ? "👹 DONJON ROUGE ($_rank)" : "☠️ DONJON RANG $_rank";
    String body = isRed ? "DANGER ! Difficulté accrue, butin rare !" : "Survis à ce donjon, Chasseur.";
    
    NotificationService.showNotification(title, body, type: 'dungeon');

    // VIBRATION DONJON : 1.5s - 0.5s pause - 1.5s
    if (await Vibration.hasVibrator() ?? false) {
       Vibration.vibrate(pattern: [0, 1500, 500, 1500]); 
    }
    
    _activeThreats.add(d);
    notifyListeners();
  }
  
  void debugTriggerRankedQuest() { _urgentQuestProvider?.triggerRankedQuest(_rank); }
  void addKey(String k, int c) { _inventoryKeys[k] = (_inventoryKeys[k] ?? 0) + c; notifyListeners(); }
  void toggleRunTracking() { _isTracking = !_isTracking; notifyListeners(); }
  void addReps(String type, int amount) { incrementExercise(type); }
  void trainAllManualExercises() { incrementExercise("Pompes"); incrementExercise("Abdos"); incrementExercise("Squats"); }
  void closeResultScreen() { _dungeonResult = null; notifyListeners(); }
  void equipTitle(String t) { if (_unlockedTitles.contains(t)) { _equippedTitle = t; _saveData(); notifyListeners(); } }
  void setUrgentQuestProvider(UrgentQuestProvider p) { _urgentQuestProvider = p; _urgentQuestProvider!.onTimeExpired = () { fleeUrgentQuest(isTimeout: true); }; }
  
  // --- METHODE DE MODIFICATION MANUELLE DES STATS ---
  void updateTotalStat(String type, double value) {
      if (type == 'POMPES') _totalPompes = value.toInt();
      else if (type == 'ABDOS') _totalAbdos = value.toInt();
      else if (type == 'SQUATS') _totalSquats = value.toInt();
      else if (type == 'ENDURANCE') _totalKm = value;
      else if (type == 'DISCIPLINE') _streak = value.toInt();
      else if (type == 'XP') _xp = value; // AJOUT : Modification de l'XP
      
      _saveData();
      notifyListeners();
  }

  // --- METHODE POUR LE CALENDRIER MANUEL (AVEC SÉCURITÉ DE SYNCHRO) ---
  void updateHistoryStatus(String dateKey, String status) {
      // Ajoute ou modifie une entrée dans l'historique
      _calendarHistory[dateKey] = {
          'status': status,
          'recordBroken': false // On met false par défaut pour une entrée manuelle
      };
      
      // SÉCURITÉ : Si on passe manuellement AUJOURD'HUI en GOLD
      // On s'assure que le compteur de cycle est cohérent (minimum 1)
      // Mais on ne donne pas d'XP pour éviter la triche infinie
      if (dateKey == _getTodayKey() && status == 'gold') {
        if (_dailyCyclesCompleted == 0) {
          _dailyCyclesCompleted = 1;
          print("--- 🛡️ SYNCHRO MANUELLE : Calendrier passé en OR -> Cycle forcé à 1 (0 XP) ---");
        }
      }
      
      _saveData();
      notifyListeners();
  }

  void startClassChange() { 
      if (_isClassChangeStarted) return;
      _isClassChangeStarted = true;
      _classChangeEndTime = DateTime.now().add(const Duration(hours: 48)); 
      _saveData(); 
      notifyListeners(); 
  }
  
  void completeClassChange() { 
      _rank = "NATION"; 
      _xp = 7500000001; 
      _syncStatsToRank(); 
      _isClassChangeStarted = false;
      _classChangeEndTime = null; 
      if (!_unlockedTitles.contains("Autorité Nationale")) { _unlockedTitles.add("Autorité Nationale"); }
      _equippedTitle = "Autorité Nationale";
      _lastRankUp = "NATION";
      _showLevelUpOverlay = true; 
      AudioService.playNationGoal(); // SON SPÉCIAL NATION
      
      // --- NOTIF PERSONNALISÉE ---
      NotificationService.showNotification("ÉVEIL NATIONAL", "L'humanité vous regarde, $_username.", type: 'levelup');
      
      _saveData(); notifyListeners(); 
  }
  
  void applyFailurePenalty() {
    double penalty = 100000000; // 100 MILLIONS
    _xp = (_xp - penalty).clamp(currentRankFloor, 7500000000);
    _coins = (_coins / 2).round();
    _isClassChangeStarted = false;
    _classChangeEndTime = null;
    _classChangeKm = 0;
    _classChangePompes = 0;
    _classChangeAbdos = 0;
    _classChangeSquats = 0;
    _currentHp = _maxHp;
    AudioService.playDefeat(); // SON DEFAITE
    _saveData(); notifyListeners();
  }
  
  void checkAwakeningFailure() {
    if (_isClassChangeStarted && formattedRemainingTime == "00:00:00") {
        if (_currentHp > 1) {
            bool isCompleted = _classChangeKm >= goalNationKm &&
                 _classChangePompes >= goalNationPompes &&
                 _classChangeAbdos >= goalNationAbdos &&
                 _classChangeSquats >= goalNationSquats;
            if (!isCompleted) {
                _currentHp = 1; 
                NotificationService.showNotification("ÉCHEC CRITIQUE", "Le temps est écoulé. Pénalité imminente.", type: 'penalty');
                AudioService.playDefeat();
                notifyListeners();
                _saveData();
            }
        }
    }
  }
  
  // --- CORRECTION BUG PSEUDO "CHASSEUR" ---
  void updateUsername(String newName) async { 
    print("--- 🔄 CHANGEMENT NOM: $newName ---");
    _username = newName; 
    notifyListeners(); 

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 2. Sauvegarde FORCEE sur les deux clés
      await prefs.setString('player_name_v2', newName); 
      await prefs.setString('username', newName); 
      
      print("--- ✅ NOM SAUVEGARDÉ SUR DISQUE (CONFIRMÉ) : $newName ---");
      await _saveData(); 
    } catch (e) {
      print("--- ❌ ERREUR LORS DE LA SAUVEGARDE DU NOM : $e ---");
    }
  }
  
  bool buyItem(String name) {
    int cost = 0; String n = name.toLowerCase();
    
    if (n.contains("mineure")) cost = priceMinorPotion;
    else if (n.contains("majeure")) cost = priceMajorPotion;
    else if (n.contains("guérison")) cost = priceFullHeal;

    // --- CORRECTION : Empêcher l'achat si santé pleine ---
    if (_currentHp >= _maxHp) {
        return false; // Retourne faux si santé déjà au max
    }
    // -----------------------------------------------------

    if (_coins >= cost && cost > 0) {
      _coins -= cost;
      if (n.contains("mineure")) _currentHp = (_currentHp + 50).clamp(0, _maxHp);
      else if (n.contains("majeure")) _currentHp = (_currentHp + 200).clamp(0, _maxHp);
      else if (n.contains("guérison")) _currentHp = _maxHp;
      
      _saveData(); 
      notifyListeners(); 
      return true; 
    }
    return false;
  }
  
  int _getMaxHpForRank(String r) { switch(r) { case 'E': return 100; case 'D': return 200; case 'C': return 500; case 'B': return 1000; case 'A': return 2000; case 'S': return 5000; case 'NATION': return 20000; default: return 100; } }

  void deleteHistoryEntry(String dateKey) {
     if (_calendarHistory.containsKey(dateKey)) {
         _calendarHistory.remove(dateKey);
         _saveData();
         notifyListeners();
     }
  }

  // --- LIFECYCLE MANAGEMENT ---
  // Ajout de cette méthode pour détecter quand l'app revient de l'arrière-plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("--- 📲 APPLICATION REPRISE (FOREGROUND) ---");
      checkMidnightReset(); // Vérifie la date immédiatement
      _startSensorInternal(); // Relance le podomètre si nécessaire
      
      // --- APPEL CRITIQUE : VERIFIE LA COULEUR AU RETOUR DANS L'APP ---
      _updateCalendarActivity(); 
      
      // Sécurité supplémentaire au resume : synchro si GOLD
      _syncCycleWithCalendar();
      
      _updateOngoingSystem(); // Force l'update notif
    }
  }

  GameProvider() { 
    WidgetsBinding.instance.addObserver(this); 
    initializeGame(); 
  }
  
  // --- INITIALISATION DU JEU AVEC PERMISSIONS ---
  Future<void> initializeGame() async { 
    await _loadData(); 
    await _requestPermissions(); // DEMANDE D'ACCES SYSTEME
    _startSensorInternal(); 
    // AJOUT : Vérification immédiate au lancement (Cold Start)
    checkMidnightReset();
    _updateOngoingSystem();
  }
  
  // --- NOUVEAU : NETTOYAGE DU CALENDRIER (70 JOURS MAX) ---
  void _pruneCalendarHistory() {
    final now = DateTime.now();
    // On garde 70 jours en arrière pour la Heatmap
    final cutoffDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 70));
    List<String> keysToRemove = [];
    
    _calendarHistory.forEach((dateKey, value) {
      try {
        DateTime entryDate = DateTime.parse(dateKey);
        if (entryDate.isBefore(cutoffDate)) {
          keysToRemove.add(dateKey);
        }
      } catch (e) {
        keysToRemove.add(dateKey);
      }
    });

    for (String key in keysToRemove) {
      _calendarHistory.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      print("--- 🧹 NETTOYAGE SYSTÈME : ${keysToRemove.length} anciennes entrées supprimées ---");
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // --- AJOUT : CHARGEMENT DU MOT DE PASSE ADMIN ---
    _adminPassword = prefs.getString('admin_password') ?? "SOLO";

    // --- CORRECTION BUG CHARGEMENT NOM ---
    String? savedName = prefs.getString('player_name_v2'); 
    String? backupName = prefs.getString('username');
    print("DEBUG CHARGEMENT -> Principal: '$savedName' | Backup: '$backupName'");

    if (savedName == "Chasseur" && backupName != null && backupName != "Chasseur" && backupName != "JIN-WOO") {
        _username = backupName;
    } 
    else if (savedName == null || savedName.isEmpty || savedName == "JIN-WOO" || savedName == "Chargement...") {
        if (backupName != null && backupName.isNotEmpty && backupName != "JIN-WOO") {
             _username = backupName;
        } else {
             _username = "Chasseur"; 
        }
    } else {
        _username = savedName;
    }
    
    _rank = prefs.getString('rank') ?? "E";
    _currentHp = prefs.getInt('hp') ?? 100;
    _maxHp = prefs.getInt('maxHp') ?? 100; 
    _streak = prefs.getInt('streak') ?? 0;
    _lastResetDateStr = prefs.getString('lastResetDate');
    _isInPenaltyZone = prefs.getBool('isInPenaltyZone') ?? false;
    _penaltySquatsDone = prefs.getInt('penaltySquatsDone') ?? 0;
    _dailyCyclesCompleted = prefs.getInt('dailyCyclesCompleted') ?? 0;
    _kmConsumedByDaily = prefs.getDouble('kmConsumedByDaily') ?? 0.0;
    _pompes = prefs.getInt('dailyPompes') ?? 0;
    _abdos = prefs.getInt('dailyAbdos') ?? 0;
    _squats = prefs.getInt('dailySquats') ?? 0;
    _dailySteps = prefs.getInt('dailySteps') ?? 0;
    _sessionKm = prefs.getDouble('sessionKm') ?? 0.0;
    _dungeonsCompleted = prefs.getInt('dungeonsCompleted') ?? 0; 
    
    String? invString = prefs.getString('inventoryKeys');
    if (invString != null) { Map<String, dynamic> decoded = jsonDecode(invString); _inventoryKeys = decoded.map((key, value) => MapEntry(key, value as int)); }
    
    var rawXp = prefs.get('xp');
    if (rawXp is num) _xp = rawXp.toDouble(); else _xp = 0.0;

    var rawCoins = prefs.get('coins');
    if (rawCoins is num) _coins = rawCoins.toInt(); else _coins = 0;

    // Chargement de l'historique SAVE
    String? historyStr = prefs.getString('saveHistory');
    if (historyStr != null) {
        _saveHistory = List<Map<String, dynamic>>.from(jsonDecode(historyStr));
    }

    // Chargement CALENDRIER & RECORDS
    String? calStr = prefs.getString('calendarHistory');
    if (calStr != null) _calendarHistory = jsonDecode(calStr);
    
    _maxPompes = prefs.getInt('maxPompes') ?? 0;
    _maxAbdos = prefs.getInt('maxAbdos') ?? 0;
    _maxSquats = prefs.getInt('maxSquats') ?? 0;
    _maxKm = prefs.getDouble('maxKm') ?? 0.0;

    // Chargement des totaux cumulés
    _totalPompes = prefs.getInt('totalPompes') ?? 0;
    _totalAbdos = prefs.getInt('totalAbdos') ?? 0;
    _totalSquats = prefs.getInt('totalSquats') ?? 0;
    _totalKm = prefs.getDouble('totalKm') ?? 0.0;

    // Chargement du SURPASSEMENT TOTAL
    _totalSurpassement = prefs.getInt('totalSurpassement') ?? 0;

    if (prefs.containsKey('classChangeEndTime')) { 
        String? dateStr = prefs.getString('classChangeEndTime'); 
        if (dateStr != null) _classChangeEndTime = DateTime.parse(dateStr); 
        _isClassChangeStarted = true; 
    } else {
        _isClassChangeStarted = false;
    }
    _classChangePompes = prefs.getInt('classChangePompes') ?? 0; 
    _classChangeAbdos = prefs.getInt('classChangeAbdos') ?? 0;
    _classChangeSquats = prefs.getInt('classChangeSquats') ?? 0; 
    _classChangeKm = prefs.getDouble('classChangeKm') ?? 0.0;
    
    _syncStatsToRank();
    
    // --- MODE TRICHE (DÉSACTIVÉ PAR DÉFAUT) ---
    bool activateCheatMode = false; 

    if (activateCheatMode) {
      print("--- ⚠️ INJECTION DU MODE TRICHE ACTIVE ⚠️ ---");
      _username = "Mathis"; 
      _rank = "E";
      _xp = 3910; 
      _coins = 100; 
      _currentHp = 100;
      _maxHp = 100;
      _dailyCyclesCompleted = 0;
      _streak = 3; // On simule 3 jours de streak
      _sessionKm = 2.818;
      _dailySteps = 2200;
      _isInPenaltyZone = false; 
      
      // IMPORTANT : ON SET LA DATE DE RESET A AUJOURD'HUI POUR EVITER LE DECALAGE AUTOMATIQUE QUI ECRASE TOUT
      _lastResetDateStr = DateTime.now().toIso8601String().split('T')[0]; 
      
      _inventoryKeys = {"E": 2, "D": 0, "C": 0, "B": 0, "A": 0, "S": 0, "NATION": 0};
      _isClassChangeStarted = false;
      _classChangeEndTime = null;
      
      // --- REINITIALISATION FORCEE DE L'HISTORIQUE ---
      _calendarHistory.clear(); // ON VIDE TOUT D'ABORD
      
      DateTime now = DateTime.now();
      // On ajoute J-1, J-2, J-3 en OR
      for (int i = 1; i <= 3; i++) {
          String pastKey = now.subtract(Duration(days: i)).toIso8601String().split('T')[0];
          _calendarHistory[pastKey] = {'status': 'gold', 'recordBroken': true};
      }
      
      await _saveData(); 
      print("--- ✅ DONNÉES SAUVEGARDÉES (SECURE + HISTORIQUE RESET & INJECTÉ) ---");
      notifyListeners(); // Mise à jour immédiate UI
    } else {
      print("--- CHARGEMENT NORMAL REUSSI ---");
      print("JOUEUR : $_username | OR : $_coins | XP : $_xp");
    }
    
    _checkRankUp(); 
    _midnightTimer = Timer.periodic(const Duration(seconds: 1), (timer) => checkMidnightReset());
    
    // --- APPEL CRITIQUE : VERIFIE LA COULEUR DES QUE L'APP S'OUVRE ---
    // Cette fonction contient maintenant les logs DEBUG qui vont s'afficher dans ta console
    _updateCalendarActivity(); 
    
    // SÉCURITÉ AU CHARGEMENT
    _syncCycleWithCalendar();
    
    notifyListeners();
  }

  Future<void> _saveData() async {
    // --- NETTOYAGE AVANT SAUVEGARDE ---
    _pruneCalendarHistory();

    final prefs = await SharedPreferences.getInstance();

    // --- AJOUT : SAUVEGARDE DU MOT DE PASSE ADMIN ---
    await prefs.setString('admin_password', _adminPassword);

    if (_username != "Chargement..." && _username.isNotEmpty) {
        await prefs.setString('player_name_v2', _username); 
        await prefs.setString('username', _username); 
    }
    await prefs.setDouble('xp', _xp);
    await prefs.setString('rank', _rank);
    await prefs.setInt('coins', _coins);
    await prefs.setInt('hp', _currentHp); 
    await prefs.setInt('maxHp', _maxHp);
    await prefs.setInt('streak', _streak); 
    await prefs.setString('lastResetDate', _lastResetDateStr ?? "");
    await prefs.setString('inventoryKeys', jsonEncode(_inventoryKeys));
    await prefs.setBool('isInPenaltyZone', _isInPenaltyZone);
    await prefs.setInt('penaltySquatsDone', _penaltySquatsDone);
    await prefs.setInt('dailyCyclesCompleted', _dailyCyclesCompleted);
    await prefs.setDouble('kmConsumedByDaily', _kmConsumedByDaily);
    await prefs.setInt('dailyPompes', _pompes); 
    await prefs.setInt('dailyAbdos', _abdos); 
    await prefs.setInt('dailySquats', _squats);
    await prefs.setInt('dailySteps', _dailySteps); 
    await prefs.setDouble('sessionKm', _sessionKm);
    await prefs.setInt('dungeonsCompleted', _dungeonsCompleted); 
    
    // Sauvegarde des stats cumulées
    await prefs.setInt('totalPompes', _totalPompes);
    await prefs.setInt('totalAbdos', _totalAbdos);
    await prefs.setInt('totalSquats', _totalSquats);
    await prefs.setDouble('totalKm', _totalKm);
    
    // Sauvegarde Surpassement
    await prefs.setInt('totalSurpassement', _totalSurpassement);

    // Sauvegarde de l'historique ET des stats
    await prefs.setString('saveHistory', jsonEncode(_saveHistory));
    await prefs.setString('calendarHistory', jsonEncode(_calendarHistory));
    
    await prefs.setInt('maxPompes', _maxPompes);
    await prefs.setInt('maxAbdos', _maxAbdos);
    await prefs.setInt('maxSquats', _maxSquats);
    await prefs.setDouble('maxKm', _maxKm);

    if (_classChangeEndTime != null) { 
        await prefs.setString('classChangeEndTime', _classChangeEndTime!.toIso8601String()); 
    } else { 
        await prefs.remove('classChangeEndTime'); 
    }
    await prefs.setInt('classChangePompes', _classChangePompes); 
    await prefs.setInt('classChangeAbdos', _classChangeAbdos);
    await prefs.setInt('classChangeSquats', _classChangeSquats); 
    await prefs.setDouble('classChangeKm', _classChangeKm);
  }

  // --- SYSTÈME D'EXPORT/IMPORT DE SAUVEGARDE (COMPLET) ---
  
  // Génère un code Base64 et l'ajoute à l'historique
  String exportSaveCode() {
    Map<String, dynamic> data = {
      'username': _username,
      'rank': _rank,
      'xp': _xp,
      'coins': _coins,
      'hp': _currentHp,
      'maxHp': _maxHp,
      'streak': _streak,
      'inventoryKeys': _inventoryKeys,
      
      // AJOUT : Sauvegarde de la progression quotidienne et des cycles
      'dailyPompes': _pompes,
      'dailyAbdos': _abdos,
      'dailySquats': _squats,
      'dailySteps': _dailySteps,
      'sessionKm': _sessionKm,
      'dailyCyclesCompleted': _dailyCyclesCompleted,
      'kmConsumedByDaily': _kmConsumedByDaily,
      'penaltySquatsDone': _penaltySquatsDone,
      'isInPenaltyZone': _isInPenaltyZone,

      // AJOUT : Sauvegarde des totaux cumulés
      'totalPompes': _totalPompes,
      'totalAbdos': _totalAbdos,
      'totalSquats': _totalSquats,
      'totalKm': _totalKm,
      
      'totalSurpassement': _totalSurpassement,

      'dungeonsCompleted': _dungeonsCompleted,
      'calendarHistory': _calendarHistory, 
      'maxStats': {'p': _maxPompes, 'a': _maxAbdos, 's': _maxSquats, 'k': _maxKm},
      
      // AJOUT : Sauvegarde de la quête de classe
      'classChange': {
        'started': _isClassChangeStarted,
        'p': _classChangePompes,
        'a': _classChangeAbdos,
        's': _classChangeSquats,
        'k': _classChangeKm,
        'end': _classChangeEndTime?.toIso8601String(),
      },
      'exportDate': DateTime.now().toIso8601String(),
    };
    
    String jsonString = jsonEncode(data);
    String base64Code = base64Encode(utf8.encode(jsonString));

    // Ajouter à l'historique
    addToHistory(base64Code);

    return base64Code;
  }

  void addToHistory(String code) {
    Map<String, dynamic> entry = {
      'date': DateTime.now().toIso8601String(),
      'code': code,
      'rank': _rank,
      'xp': _xp,
      'username': _username
    };
    _saveHistory.insert(0, entry); // Ajouter au début
    if (_saveHistory.length > 3) {
      _saveHistory.removeLast(); // Garder max 3
    }
    _saveData(); // Sauvegarder la nouvelle liste
    notifyListeners();
  }

  // Lit un code Base64 et restaure les données (COMPLET)
  Future<bool> importSaveCode(String code) async {
    try {
      String jsonString = utf8.decode(base64Decode(code));
      Map<String, dynamic> data = jsonDecode(jsonString);
      
      _username = data['username'] ?? "Chasseur";
      _rank = data['rank'] ?? "E";
      _xp = (data['xp'] as num).toDouble();
      _coins = data['coins'] ?? 0;
      _currentHp = data['hp'] ?? 100;
      _maxHp = data['maxHp'] ?? 100;
      _streak = data['streak'] ?? 0;
      
      if (data['inventoryKeys'] != null) {
         Map<String, dynamic> keys = data['inventoryKeys'];
         _inventoryKeys = keys.map((k, v) => MapEntry(k, v as int));
      }
      
      // RESTAURATION : Stats quotidiennes
      _pompes = data['dailyPompes'] ?? 0;
      _abdos = data['dailyAbdos'] ?? 0;
      _squats = data['dailySquats'] ?? 0;
      _dailySteps = data['dailySteps'] ?? 0;
      _sessionKm = (data['sessionKm'] as num?)?.toDouble() ?? 0.0;
      _dailyCyclesCompleted = data['dailyCyclesCompleted'] ?? 0;
      _kmConsumedByDaily = (data['kmConsumedByDaily'] as num?)?.toDouble() ?? 0.0;
      _penaltySquatsDone = data['penaltySquatsDone'] ?? 0;
      _isInPenaltyZone = data['isInPenaltyZone'] ?? false;

      // RESTAURATION : Stats cumulées
      _totalPompes = data['totalPompes'] ?? 0;
      _totalAbdos = data['totalAbdos'] ?? 0;
      _totalSquats = data['totalSquats'] ?? 0;
      _totalKm = (data['totalKm'] as num?)?.toDouble() ?? 0.0;
      
      _totalSurpassement = data['totalSurpassement'] ?? 0;

      _dungeonsCompleted = data['dungeonsCompleted'] ?? 0;

      if (data['calendarHistory'] != null) {
          _calendarHistory = data['calendarHistory'];
      }
      if (data['maxStats'] != null) {
          Map<String, dynamic> m = data['maxStats'];
          _maxPompes = m['p'] ?? 0;
          _maxAbdos = m['a'] ?? 0;
          _maxSquats = m['s'] ?? 0;
          _maxKm = (m['k'] as num).toDouble();
      }

      // RESTAURATION : Quête de classe
      if (data['classChange'] != null) {
          Map<String, dynamic> cc = data['classChange'];
          _isClassChangeStarted = cc['started'] ?? false;
          _classChangePompes = cc['p'] ?? 0;
          _classChangeAbdos = cc['a'] ?? 0;
          _classChangeSquats = cc['s'] ?? 0;
          _classChangeKm = (cc['k'] as num).toDouble();
          if (cc['end'] != null) {
             _classChangeEndTime = DateTime.parse(cc['end']);
          }
      }

      await _saveData();
      _syncStatsToRank(); 
      _updateOngoingSystem(); // Mise à jour de la notif
      notifyListeners();
      return true;
    } catch (e) {
      print("Erreur Import: $e");
      return false;
    }
  }

  @override void dispose() { _stepSubscription?.cancel(); _dungeonTimer?.cancel(); _midnightTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
}