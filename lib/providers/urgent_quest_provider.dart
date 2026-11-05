// lib/providers/urgent_quest_provider.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../core/balance.dart';
import '../core/json_utils.dart';
import '../core/log.dart';
import '../services/notification_service.dart';

enum QuestStatus { inactive, active, success, failed }

class UrgentQuestProvider extends ChangeNotifier {
  QuestStatus _status = QuestStatus.inactive;
  String _description = "";
  double _targetAmount = 0;
  double _progress = 0;
  String _type = "";
  
  // NOUVEAUTÉ : Mise en cache des gains pour affichage exact dans l'overlay
  int _lastXpReward = 0;
  int _lastGoldReward = 0;

  DateTime? _endsAt;
  Timer? _timer;

  VoidCallback? onTimeExpired;
  Function(double xp, int gold)? onQuestSuccess;
  VoidCallback? onChanged;

  bool get isActive => _status == QuestStatus.active;
  bool get isCompleted => _progress >= _targetAmount && _targetAmount > 0;

  QuestStatus get status => _status;
  String get description => _description;
  double get targetAmount => _targetAmount;
  double get progress => _progress;
  String get type => _type;
  int get lastXpReward => _lastXpReward;
  int get lastGoldReward => _lastGoldReward;

  int get remainingSeconds {
    if (_endsAt == null) return 0;
    final int ms = _endsAt!.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  String get timeLeft {
    final int s = remainingSeconds;
    return "${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";
  }

  Future<void> triggerRankedQuest(String rank) async {
    if (isActive) return;

    final double multiplier = Balance.of(rank).urgentMultiplier;
    final int rand = Random().nextInt(4);
    int duration;

    if (rand == 0) {
      _type = "Steps";
      _targetAmount = (50 * multiplier).toDouble();
      duration = (_targetAmount / 1.5).toInt() + 30;
      _description = "URGENCE ! Faites ${_targetAmount.toInt()} pas !";
    } else if (rand == 1) {
      _type = "Distance";
      final double rawDist = max(0.05, 0.05 * multiplier);
      _targetAmount = double.parse(rawDist.toStringAsFixed(2));
      duration = (rawDist * 1000 / 1.2).toInt() + 45;
      _description = "FUITE ! Parcourez ${_targetAmount.toStringAsFixed(2)} km !";
    } else if (rand == 2) {
      _type = "Pompes";
      _targetAmount = (5 * multiplier).clamp(5, 100).toDouble();
      duration = (_targetAmount * 3).toInt() + 20;
      _description = "COMBAT ! Faites ${_targetAmount.toInt()} Pompes !";
    } else {
      _type = "Squats";
      _targetAmount = (5 * multiplier).clamp(5, 100).toDouble();
      duration = (_targetAmount * 2.5).toInt() + 20;
      _description = "ESQUIVE ! Faites ${_targetAmount.toInt()} Squats !";
    }

    _status = QuestStatus.active;
    _endsAt = DateTime.now().add(Duration(seconds: duration));
    _progress = 0;
    _lastXpReward = 0;
    _lastGoldReward = 0;

    try {
      await NotificationService.showNotification("QUÊTE URGENTE", _description, type: 'urgent');
    } catch (e) {
      dlog("Erreur notif: $e");
    }

    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 1000, 400, 1000, 400, 1000]);
    }

    _startTimer();
    notifyListeners();
    onChanged?.call();
  }

  Future<void> spawnTestUrgentQuest() async {
    await triggerRankedQuest("E");
  }

  void addProgress(double amount, String inputType) {
    if (!isActive) return;
    bool isMatch = false;
    final String goalType = _type.toLowerCase();
    final String incomingType = inputType.toLowerCase();

    if (goalType == "steps" && (incomingType.contains("pas") || incomingType.contains("steps"))) {
      isMatch = true;
    } else if (goalType == "distance" && (incomingType.contains("km") || incomingType.contains("distance"))) {
      isMatch = true;
    } else if (goalType == incomingType) {
      isMatch = true;
    }

    if (isMatch) {
      _progress = (_progress + amount).clamp(0.0, _targetAmount).toDouble();
      if (_progress >= _targetAmount) {
        _completeQuest(); 
      }
      notifyListeners();
      onChanged?.call();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isActive) {
        timer.cancel();
        return;
      }
      if (remainingSeconds > 0) {
        notifyListeners();
      } else {
        timer.cancel();
        _expire();
      }
    });
  }

  void _expire() {
    if (onTimeExpired != null) onTimeExpired!();
    if (_status == QuestStatus.active) _failQuest();
  }

  void checkExpired() {
    if (isActive && remainingSeconds <= 0) {
      _timer?.cancel();
      _expire();
    }
  }

  void _completeQuest() async {
    _timer?.cancel();
    _status = QuestStatus.success;
    
    double xpReward = 0;
    int goldReward = 0;
    
    if (_type == "Pompes") {
      xpReward = _targetAmount * 30; 
      goldReward = _targetAmount.toInt();
    } else if (_type == "Squats") {
      xpReward = _targetAmount * 25; 
      goldReward = (_targetAmount * 0.8).toInt();
    } else if (_type == "Distance") {
      xpReward = _targetAmount * 15000; 
      goldReward = (_targetAmount * 50).toInt();
    } else if (_type == "Steps") {
      xpReward = _targetAmount * 2;
      goldReward = (_targetAmount * 0.05).toInt();
    }
    
    xpReward += 150;
    goldReward += 5;

    // Sauvegarde en cache pour affichage par l'overlay sans recalcul
    _lastXpReward = xpReward.toInt();
    _lastGoldReward = goldReward;

    if (onQuestSuccess != null) {
      onQuestSuccess!(xpReward, goldReward);
    }
    
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 200, 100, 200]);
    }

    notifyListeners();
    onChanged?.call();
    
    Future.delayed(const Duration(seconds: 3), () => resetStatus());
  }

  void _failQuest() async {
    _timer?.cancel();
    _status = QuestStatus.failed;
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 1000);
    }
    notifyListeners();
    onChanged?.call();
    Future.delayed(const Duration(seconds: 4), () => resetStatus());
  }

  void fail() {
    if (_status == QuestStatus.failed) return;
    _failQuest();
  }

  void resetStatus() {
    _status = QuestStatus.inactive;
    _timer?.cancel();
    _progress = 0;
    _targetAmount = 0;
    _type = "";
    _description = "";
    _endsAt = null;
    notifyListeners();
    onChanged?.call();
  }

  Map<String, dynamic>? toJson() {
    if (!isActive || _endsAt == null) return null;
    return {
      'type': _type,
      'target': _targetAmount,
      'progress': _progress,
      'description': _description,
      'endsAt': _endsAt!.toIso8601String(),
    };
  }

  void restore(Map<String, dynamic> json) {
    final DateTime? end = DateTime.tryParse(asString(json['endsAt']));
    if (end == null) return;
    _type = asString(json['type']);
    _targetAmount = asDouble(json['target']);
    _progress = asDouble(json['progress']);
    _description = asString(json['description']);
    _endsAt = end;
    _status = QuestStatus.active;
    _startTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}