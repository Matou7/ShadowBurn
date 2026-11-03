// lib/providers/game/game_day.dart

part of '../game_provider.dart';

mixin _DayLogic on _GameBase {
  /// Initialise le premier jour en zone blanche (immunité totale jusqu'au lendemain minuit)
  void initializeFirstDay(String dateStr) {
    _lastResetDateStr = dateStr;
    _isInPenaltyZone = false;
    _penaltySquatsDone = 0;

    _calendarHistory[dateStr] = {
      'status': 'white_zone',
      'recordBroken': false,
    };

    _saveNow();
    _notify();
  }

  @override
  void toggleRunTracking() {
    _isTracking = !_isTracking;
    _requestSave();
    _notify();
  }

  @override
  void addReps(String type, int count) {
    final t = type.toLowerCase();

    // 1. ISOLATION ZONE DE PÉNALITÉ : Priorité absolue, aucun XP, aucun contournement.
    if (_isInPenaltyZone) {
      if (t.contains("squat")) {
        processPenaltySquats(count);
      }
      // On bloque immédiatement : aucun gain d'XP ou d'effort quotidien n'est compté en zone de pénalité.
      return;
    }

    // 2. ISOLATION STRICTE DONJON
    if (_activeDungeon != null) {
      final dungeon = _activeDungeon!;
      for (int i = 0; i < dungeon.tasks.length; i++) {
        final taskType = (dungeon.tasks[i]['type'] as String? ?? '').toLowerCase();
        if ((t.contains("pompe") && taskType.contains("pompe")) ||
            (t.contains("abdo") && taskType.contains("abdo")) ||
            (t.contains("squat") && taskType.contains("squat"))) {
          final double maxReq = (dungeon.tasks[i]['amount'] as num).toDouble();
          dungeon.progress[i] = (dungeon.progress[i] + count).clamp(0.0, maxReq);
        }
      }

      _xp += 5 * _vitality;
      _checkDungeonStatus();
      _checkTitles(silent: true);
      _requestSave();
      _notify();
      return;
    }

    // 3. QUÊTE QUOTIDIENNE NORMALE
    if (t.contains("pompe")) {
      _pompes += count;
      _totalPompes += count;
      if (_pompes > _maxPompes) {
        _maxPompes = _pompes;
        _recordBrokenToday = true;
      }
    } else if (t.contains("abdo")) {
      _abdos += count;
      _totalAbdos += count;
      if (_abdos > _maxAbdos) {
        _maxAbdos = _abdos;
        _recordBrokenToday = true;
      }
    } else if (t.contains("squat")) {
      _squats += count;
      _totalSquats += count;
      if (_squats > _maxSquats) {
        _maxSquats = _squats;
        _recordBrokenToday = true;
      }
    }

    _xp += 5 * _vitality;
    _updateCalendarActivity();
    _checkCycleCompletion();
    _checkTitles(silent: true);
    _requestSave();
    _notify();
  }

  @override
  void incrementExercise(String type) {
    if (_isClassChangeStarted) {
      final t = type.toLowerCase();
      if (t.contains("pompe")) {
        _classChangePompes += 5;
      } else if (t.contains("abdo")) {
        _classChangeAbdos += 5;
      } else if (t.contains("squat")) {
        _classChangeSquats += 5;
      }
      _saveNow();
      _notify();
      return;
    }
    addReps(type, 5);
  }

  @override
  void trainAllManualExercises() {
    addReps("Pompes", 5);
    addReps("Abdos", 5);
    addReps("Squats", 5);
  }

  @override
  void _syncCycleWithCalendar() {
    final String today = _todayKey();
    final dynamic entry = _calendarHistory[today];
    if (entry is Map && entry['status'] == 'gold' && _dailyCyclesCompleted == 0) {
      _dailyCyclesCompleted = 1;
    }
  }

  @override
  void _updateCalendarActivity() {
    final String today = _todayKey();
    final bool kmOk = _dailyKm >= goalKm;
    final bool pompesOk = _pompes >= goalDailyExo;
    final bool abdosOk = _abdos >= goalDailyExo;
    final bool squatsOk = _squats >= goalDailyExo;

    final dynamic existingEntry = _calendarHistory[today];
    final bool alreadyGold = (existingEntry is Map && existingEntry['status'] == 'gold');

    if ((kmOk && pompesOk && abdosOk && squatsOk) || _dailyCyclesCompleted > 0 || alreadyGold) {
      _calendarHistory[today] = {
        'status': 'gold',
        'recordBroken': _recordBrokenToday,
      };
    } else {
      final bool wasWhiteZone = (existingEntry is Map && existingEntry['status'] == 'white_zone');
      _calendarHistory[today] = {
        'status': wasWhiteZone ? 'white_zone' : (_dailyKm >= goalKm ? 'blue' : 'grey'),
        'recordBroken': _recordBrokenToday,
      };
    }
  }

  @override
  Future<void> checkMidnightReset() async {
    final String today = _todayKey();
    
    // BLINDAGE ANTI-VOYAGE TEMPOREL
    final prefs = await SharedPreferences.getInstance();
    final int lastKnownMs = prefs.getInt('shadow_last_known_ms') ?? 0;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    
    if (nowMs < lastKnownMs) {
      // Le téléphone a été reculé dans le temps de façon significative (plus de 5 minutes)
      if ((lastKnownMs - nowMs) > 300000) {
        dlog("[SÉCURITÉ] Anomalie Temporelle détectée. Le temps a été altéré.");
        // Pour une app commerciale, on bloque silencieusement la validation des jours passés
        return; 
      }
    } else {
      await prefs.setInt('shadow_last_known_ms', nowMs);
    }

    if (_lastResetDateStr == null || _lastResetDateStr!.isEmpty) {
      _lastResetDateStr = today;
      await _saveNow();
      return;
    }

    if (_lastResetDateStr == today) return;

    final DateTime? lastRaw = _parseDay(_lastResetDateStr!);
    final DateTime? currentRaw = _parseDay(today);

    if (lastRaw == null || currentRaw == null) {
      _lastResetDateStr = today;
      await _saveNow();
      return;
    }

    final DateTime lastUtc = DateTime.utc(lastRaw.year, lastRaw.month, lastRaw.day);
    final DateTime currentUtc = DateTime.utc(currentRaw.year, currentRaw.month, currentRaw.day);

    final int daysDiff = currentUtc.difference(lastUtc).inDays;
    
    // ANTI-TRICHE : Empêcher le bond dans le futur
    if (daysDiff < 0) {
      dlog("[SÉCURITÉ] Retour dans le passé détecté sur la date civile.");
      return; 
    }

    if (daysDiff == 0) {
      _lastResetDateStr = today;
      return;
    }

    if (daysDiff > 7) {
      _lastResetDateStr = today;
      _pompes = 0;
      _abdos = 0;
      _squats = 0;
      _sessionKm = 0.0;
      _dailyKm = 0.0;
      _dailySteps = 0;
      _dailyCyclesCompleted = 0;
      _recordBrokenToday = false;
      _streak = 0;
      _currentStreak = 0;
      await _saveNow();
      _notify();
      return;
    }

    for (int i = 0; i < daysDiff; i++) {
      final DateTime evalDate = DateTime.utc(lastUtc.year, lastUtc.month, lastUtc.day + i);
      final String evaluatedDayKey =
          "${evalDate.year}-${evalDate.month.toString().padLeft(2, '0')}-${evalDate.day.toString().padLeft(2, '0')}";

      final dynamic histEntry = _calendarHistory[evaluatedDayKey];
      final String? existingStatus = histEntry is Map ? histEntry['status']?.toString() : null;

      final bool isWhiteZoneDay = (existingStatus == 'white_zone');
      final bool dayDone = ((i == 0) && _dailyCyclesCompleted > 0) || (existingStatus == 'gold');

      if (dayDone) {
        _calendarHistory[evaluatedDayKey] = {
          'status': 'gold',
          'recordBroken': (i == 0) ? _recordBrokenToday : (histEntry is Map ? (histEntry['recordBroken'] == true) : false),
        };
      } else if (isWhiteZoneDay) {
        _calendarHistory[evaluatedDayKey] = {
          'status': 'grey',
          'recordBroken': false,
        };
      } else {
        _streak = 0;
        _currentStreak = 0;
        _calendarHistory[evaluatedDayKey] = {
          'status': 'grey',
          'recordBroken': false,
        };
        // On ne force le lock que sur le premier jour manqué pour éviter une sur-couverture
        if (i == 0 && !_isInPenaltyZone) {
          triggerDailyPenalty();
        }
      }
    }

    _pompes = 0;
    _abdos = 0;
    _squats = 0;
    _sessionKm = 0.0;
    _dailyKm = 0.0;
    _dailySteps = 0;
    _dailyCyclesCompleted = 0;
    _recordBrokenToday = false;
    _lastResetDateStr = today;

    _updateCalendarActivity();
    await _saveNow();
    _notify();
  }

  @override
  void _checkCycleCompletion() {
    bool completedAtLeastOne = false;

    while (_dailyKm >= goalKm &&
           _pompes >= goalDailyExo &&
           _abdos >= goalDailyExo &&
           _squats >= goalDailyExo) {

      _dailyCyclesCompleted++;
      completedAtLeastOne = true;

      _triggerHapticFeedback();

      _dailyKm = (_dailyKm - goalKm).clamp(0.0, double.infinity);
      _pompes = (_pompes - goalDailyExo).clamp(0, 999999);
      _abdos = (_abdos - goalDailyExo).clamp(0, 999999);
      _squats = (_squats - goalDailyExo).clamp(0, 999999);

      if (_dailyCyclesCompleted == 1) {
        _streak++;
        _currentStreak = _streak;
        AudioService.playVictory();
        NotificationService.showNotification(
          "QUÊTE DU JOUR ACCOMPLIE",
          "Les bases de la force sont acquises.",
          type: 'normal',
        );
      }

      double surpassMult = 1.0;
      if (_dailyCyclesCompleted == 2) {
        _totalSurpassement++;
        surpassMult = 1.5;
        AudioService.playVictory();
        NotificationService.showNotification(
          "SURPASSEMENT NIVEAU 1",
          "Double cycle complété. Les limites sont brisées.",
          type: 'levelup',
        );
      } else if (_dailyCyclesCompleted >= 3) {
        _totalSurpassement++;
        surpassMult = 2.0;
        AudioService.playVictory();

        final bool dropKey = _rng.nextInt(100) < 35;
        String keyMsg = "";

        if (dropKey) {
          final String droppedRank = _rng.nextBool() ? _rank : (Balance.next(_rank) ?? _rank);
          _inventoryKeys[droppedRank] = (_inventoryKeys[droppedRank] ?? 0) + 1;
          keyMsg = "\nRÉCOMPENSE RARE : Clé de Donjon Rang $droppedRank acquise !";
        }

        NotificationService.showNotification(
          "SURPASSEMENT SUPRÊME",
          "Cycle $_dailyCyclesCompleted achevé. Limites pulvérisées !$keyMsg",
          type: 'levelup',
        );
      }

      final RankConfig cfg = _cfg;
      final int finalXp = (cfg.cycleReward * _vitality * surpassMult).toInt();
      _xp += finalXp;

      _calendarHistory[_todayKey()] = {
        'status': 'gold',
        'recordBroken': _recordBrokenToday,
      };

      _checkRankUp();
      _checkTitles(silent: true);
    }

    if (completedAtLeastOne && this is _SaveLogic) {
      (this as _SaveLogic).checkGoldGridReward();
    }

    _updateOngoingSystem();
    _requestSave();
    _notify();
  }

  void _triggerHapticFeedback() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      Vibration.hasVibrator().then((hasVibe) {
        if (hasVibe == true) {
          Vibration.vibrate(duration: 400);
        }
      });
    } catch (_) {}
  }

  @override
  void _onSteps(StepEvent e) {
    final int diff = e.delta;
    if (diff <= 0) return;

    final double kmAdded = (diff * 0.75) / 1000.0;

    _totalKm += kmAdded;
    _dailyKm += kmAdded;
    _dailySteps += diff;

    if (_isTracking) {
      _sessionKm += kmAdded;
    }

    if (_isClassChangeStarted) {
      _classChangeKm += kmAdded;
    }

    _stepBufferForXp += diff;
    if (_stepBufferForXp >= 20) {
      _xp += _stepBufferForXp * _vitality;
      _stepBufferForXp = 0;
    }

    if (_dailyKm > _maxKm) {
      _maxKm = _dailyKm;
      _recordBrokenToday = true;
    }

    _updateCalendarActivity();
    _checkCycleCompletion();
    _updateOngoingSystem();
    _requestSave();
    _notify();
  }

  @override
  void _updateOngoingSystem({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastOngoingUpdate != null &&
        now.difference(_lastOngoingUpdate!) < const Duration(seconds: 3)) {
      return;
    }
    _lastOngoingUpdate = now;

    final double p = (_pompes / max(1, goalDailyExo)).clamp(0.0, 1.0).toDouble();
    final double a = (_abdos / max(1, goalDailyExo)).clamp(0.0, 1.0).toDouble();
    final double s = (_squats / max(1, goalDailyExo)).clamp(0.0, 1.0).toDouble();
    final double k = (_dailyKm / max(0.1, goalKm)).clamp(0.0, 1.0).toDouble();

    final int avgProgress = ((p + a + s + k) / 4 * 100).toInt();

    NotificationService.updateTrackingNotification(
      "Le Système veille.",
      "Quête : $avgProgress% | Cycle : $_dailyCyclesCompleted",
      color: const Color(0xFF00E5FF),
      progress: avgProgress,
      maxProgress: 100,
    );
  }
}