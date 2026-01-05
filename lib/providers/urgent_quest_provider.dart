import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/notification_service.dart';

enum QuestStatus { inactive, active, success, failed }

class UrgentQuestProvider extends ChangeNotifier {
  QuestStatus _status = QuestStatus.inactive;
  String _description = "";
  double _targetAmount = 0;
  double _progress = 0;
  String _type = "";
  
  Timer? _timer;
  int _remainingSeconds = 0;
  int _totalDuration = 0;

  VoidCallback? onTimeExpired;

  // --- GETTERS ---
  bool get isActive => _status == QuestStatus.active;
  bool get isCompleted => _progress >= _targetAmount && _targetAmount > 0;
  
  QuestStatus get status => _status;
  String get description => _description;
  double get targetAmount => _targetAmount;
  double get progress => _progress;
  int get remainingSeconds => _remainingSeconds;
  String get type => _type;

  String get timeLeft {
    int minutes = _remainingSeconds ~/ 60;
    int seconds = _remainingSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  /// Déclenche une quête aléatoire basée sur le rang
void triggerRankedQuest(String rank) async {
    if (isActive) return;

    // Multiplicateur pour ajuster la difficulté selon le rang
    double multiplier = 1.0;
    switch (rank) {
      case "D": multiplier = 1.5; break;
      case "C": multiplier = 2.0; break;
      case "B": multiplier = 3.0; break;
      case "A": multiplier = 4.0; break;
      case "S": multiplier = 5.0; break; 
      case "NATION": multiplier = 10.0; break;
    }

    int rand = Random().nextInt(4);
    
    // Génération de l'objectif
    if (rand == 0) {
      _type = "Steps"; 
      _targetAmount = (50 * multiplier).toDouble(); 
      _totalDuration = (_targetAmount / 1.5).toInt() + 30; 
      _description = "URGENCE ! Faites ${_targetAmount.toInt()} pas !"; 
      
    } else if (rand == 1) {
      _type = "Distance"; 
      double rawDist = max(0.05, 0.05 * multiplier); 
      _targetAmount = double.parse(rawDist.toStringAsFixed(2));
      _totalDuration = (rawDist * 1000 / 1.2).toInt() + 45; 
      _description = "FUITE ! Parcourez ${_targetAmount.toStringAsFixed(2)} km !"; 
      
    } else if (rand == 2) {
      _type = "Pompes"; 
      _targetAmount = (5 * multiplier).clamp(5, 100); 
      _totalDuration = (_targetAmount * 3).toInt() + 20; 
      _description = "COMBAT ! Faites ${_targetAmount.toInt()} Pompes !"; 
      
    } else {
      _type = "Squats"; 
      _targetAmount = (5 * multiplier).clamp(5, 100); 
      _totalDuration = (_targetAmount * 2.5).toInt() + 20;
      _description = "ESQUIVE ! Faites ${_targetAmount.toInt()} Squats !"; 
    }

    _status = QuestStatus.active;
    _remainingSeconds = _totalDuration;
    _progress = 0;

    try { 
      await NotificationService.showNotification("QUÊTE URGENTE", _description, type: 'urgent'); 
    } catch (e) {
      debugPrint("Erreur notif: $e");
    }
    
    // VIBRATION QUÊTE URGENTE : 1s - 0.4s - 1s - 0.4s - 1s
    if (await Vibration.hasVibrator() ?? false) {
       Vibration.vibrate(pattern: [0, 1000, 400, 1000, 400, 1000]); 
    }
    
    _startTimer();
    notifyListeners();
  }

  void addProgress(double amount, String inputType) {
    if (!isActive) return;
    bool isMatch = false;
    String goalType = _type.toLowerCase();
    String incomingType = inputType.toLowerCase();

    if (goalType == "steps" && (incomingType.contains("pas") || incomingType.contains("steps"))) { isMatch = true; } 
    else if (goalType == "distance" && (incomingType.contains("km") || incomingType.contains("distance"))) { isMatch = true; } 
    else if (goalType == incomingType) { isMatch = true; }

    if (isMatch) {
      _progress = (_progress + amount).clamp(0.0, _targetAmount);
      // La vérification de complétion se fait ici, mais la récompense est gérée par GameProvider
      notifyListeners();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        if (onTimeExpired != null) onTimeExpired!();
        _failQuest();
      }
    });
  }

  void _completeQuest() async { 
    _timer?.cancel(); 
    _status = QuestStatus.success; 
    notifyListeners(); 
  }

  void _failQuest() async { 
    _timer?.cancel(); 
    _status = QuestStatus.failed; 
    if (await Vibration.hasVibrator() ?? false) { Vibration.vibrate(duration: 1000); }
    notifyListeners(); 
    Future.delayed(const Duration(seconds: 4), () => resetStatus()); 
  }

  void fail() { _failQuest(); }

  void resetStatus() {
    _status = QuestStatus.inactive; 
    _timer?.cancel(); 
    _progress = 0; 
    _targetAmount = 0;
    _type = ""; 
    _remainingSeconds = 0; 
    notifyListeners();
  }

  @override 
  void dispose() { 
    _timer?.cancel(); 
    super.dispose(); 
  }
}