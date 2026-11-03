// lib/providers/game/game_dungeons.dart

part of '../game_provider.dart';

mixin _DungeonLogic on _GameBase {
  Timer? _threatTimer;
  bool _isFinishingDungeon = false;

  void setUrgentQuestProvider(UrgentQuestProvider p) {
    if (_urgent == p) return;
    _urgent = p;
    p.onTimeExpired = () => fleeUrgentQuest(isTimeout: true);
    p.onChanged = _requestSave;
    final pending = _pendingUrgentJson;
    if (pending != null) {
      _pendingUrgentJson = null;
      Future.microtask(() {
        p.restore(pending);
        p.checkExpired();
      });
    }
  }

  @override
  void _rewardUrgentQuest() {
    final u = _urgent;
    if (u == null) return;

    if (_isSurpassQuest) {
      NotificationService.showNotification(
        "SURPASSEMENT RÉUSSI",
        "Bien joué $_username. Vous avez survécu à la pression.",
        type: 'levelup',
      );
      AudioService.playVictory();
      u.resetStatus();
      _isSurpassQuest = false;
      _saveNow();
      _notify();
      return;
    }

    final int finalXp = (_cfg.urgentReward * _vitality).toInt();
    _xp += finalXp;
    _coins += (20 * goldMultiplier).toInt();

    _dungeonResult = {'status': 'VICTOIRE', 'xp': finalXp};
    AudioService.playVictory();
    u.resetStatus();
    _checkRankUp();
    _saveNow();
    _notify();
  }

  void fleeUrgentQuest({bool isTimeout = false}) {
    final u = _urgent;
    if (u != null && u.isActive) {
      u.resetStatus();
      _isSurpassQuest = false;
      _saveNow();
      _notify();
    }
  }

  @override
  void debugTriggerRankedQuest() {
    _triggerHunterAlert();
    _urgent?.triggerRankedQuest(_rank);
  }

  void _triggerHunterAlert() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 1500, 800, 1500], intensities: [0, 255, 0, 255]);
    }
  }

  void enterDungeon(String k, {bool isThreat = false, Dungeon? threatInstance, bool isRed = false}) {
    if (_activeDungeon != null) return;
    if (!isThreat && (_inventoryKeys[k] ?? 0) <= 0) return;

    _isActiveDungeonRed = isRed;
    final RankConfig cfg = Balance.of(k);
    int reps = cfg.dungeonReps;
    if (isRed) reps = (reps * 1.5).toInt();

    List tasksRaw = [
      {'type': 'Pompes', 'amount': reps, 'title': 'Pompes'},
      {'type': 'Squats', 'amount': reps, 'title': 'Squats'},
      {'type': 'Abdos', 'amount': reps, 'title': 'Abdos'},
    ];

    var tasks = tasksRaw.map((e) => Map<String, dynamic>.from(e)).toList();

    final Duration dungeonDuration = _sandbox ? const Duration(seconds: 10) : const Duration(hours: 2);

    _activeDungeon = Dungeon(
      id: isThreat && threatInstance != null
          ? threatInstance.id
          : DateTime.now().millisecondsSinceEpoch.toString(),
      rank: k,
      tasks: tasks,
      progress: List.filled(tasks.length, 0.0),
      expiresAt: DateTime.now().add(dungeonDuration),
      xpReward: 0,
      penaltyXp: 0,
      isRandomThreat: isThreat,
    );
    if (!isThreat) _inventoryKeys[k] = (_inventoryKeys[k] ?? 0) - 1;

    if (isThreat && threatInstance != null) {
      _activeThreats.removeWhere((t) => t.id == threatInstance.id);
    }

    _warningGiven = false;
    LockService.lockScreen();
    _notify();
    _startDungeonTimer();

    if (_sandbox) {
      if (SandboxManager.persistPenalty) {
        SandboxManager.saveSandbox(_toJson());
      }
    } else {
      _saveNow();
    }
  }

  @override
  void _checkDungeonStatus() {
    if (_activeDungeon == null) return;
    bool allDone = true;
    for (int i = 0; i < _activeDungeon!.tasks.length; i++) {
      if (_activeDungeon!.progress[i] < (_activeDungeon!.tasks[i]['amount'] as num)) {
        allDone = false;
      }
    }

    if (allDone) {
      final bool inTime = DateTime.now().isBefore(_activeDungeon!.expiresAt);
      _finishDungeon(victory: inTime);
    }
  }

  void _finishDungeon({required bool victory}) async {
    if (_activeDungeon == null || _isFinishingDungeon) return;
    _isFinishingDungeon = true;

    int baseXP = Balance.of(_activeDungeon!.rank).dungeonReward;
    if (_isActiveDungeonRed) baseXP *= 2;

    if (victory) {
      _dungeonsCompleted++;
      final int dungeonHeal = (_maxHp * 0.2).toInt();
      _currentHp = (_currentHp + dungeonHeal).clamp(0, _maxHp).toInt();

      final int finalXp = (baseXP * _vitality).toInt();
      final int goldReward = (100 * pow(1.5, rankIndex)).toInt();
      _xp += finalXp;
      _coins += goldReward;

      String lootMsg = "";
      final int dropChance = _isActiveDungeonRed ? 30 : 15;
      if (_rng.nextInt(100) < dropChance) {
        final String? higher = Balance.next(_activeDungeon!.rank);
        if (higher != null) {
          _inventoryKeys[higher] = (_inventoryKeys[higher] ?? 0) + 1;
          lootMsg = "\nLOOT RARE : CLÉ RANG $higher";
          try {
            if (await Vibration.hasVibrator()) {
              Vibration.vibrate(pattern: [0, 100, 50, 100, 50, 200]);
            }
          } catch (_) {}
        }
      }
      _dungeonResult = {'status': 'VICTOIRE$lootMsg\n(+ $dungeonHeal HP)', 'xp': finalXp};
      AudioService.playVictory();
      _checkRankUp();
      _checkTitles();
    } else {
      final int penaltyXp = (baseXP * 0.75).toInt();
      _loseXp(penaltyXp);
      _dungeonResult = {
        'status': 'PORTAIL FERMÉ EN RETARD\nQuota atteint hors délai imparti.',
        'xp': -penaltyXp,
      };
      AudioService.playDefeat();
    }

    try {
      await LockService.unlockScreen();
    } catch (_) {}

    _activeDungeon = null;
    _isActiveDungeonRed = false;
    _dungeonTimer?.cancel();
    _notify();

    if (_sandbox) {
      if (SandboxManager.persistPenalty) {
        SandboxManager.saveSandbox(_toJson());
      }
    } else {
      _saveNow();
    }

    _isFinishingDungeon = false;
  }

  void leaveDungeon() {
    NotificationService.showNotification(
      "ACCÈS REFUSÉ",
      "Le Système interdit la fuite. Achevez le quota imposé ou utilisez l'Amnistie Système.",
      type: 'penalty',
    );
  }

  @override
  void _startDungeonTimer() {
    _dungeonTimer?.cancel();
    _dungeonTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDungeon == null) {
        timer.cancel();
      } else {
        _notify();
      }
    });
  }

  @override
  void debugForceSpawnThreat({bool isRed = false}) async {
    final Duration threatDuration = _sandbox ? const Duration(seconds: 10) : const Duration(hours: 2);
    final DateTime expiry = DateTime.now().add(threatDuration);

    final Dungeon d = Dungeon(
      id: 'threat_${DateTime.now().millisecondsSinceEpoch}',
      rank: _rank,
      tasks: [],
      progress: [],
      expiresAt: expiry,
      xpReward: 0,
      penaltyXp: 0,
      isRandomThreat: true,
    );

    final String timeLabel = _sandbox ? "10 secondes" : "2 heures";
    final String title = isRed ? "👹 DONJON ROUGE ($_rank)" : "☠️ DONJON RANG $_rank";
    final String body = isRed
        ? "PORTAIL APPARU ! $timeLabel avant l'aspiration automatique."
        : "Un donjon est apparu dans vos menaces ($timeLabel).";
    NotificationService.showNotification(title, body, type: 'dungeon');
    _triggerHunterAlert();

    _activeThreats.add(d);

    if (_sandbox) {
      if (SandboxManager.persistPenalty) {
        SandboxManager.saveSandbox(_toJson());
      }
    } else {
      _requestSave();
    }
    _notify();

    _threatTimer?.cancel();
    _threatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDungeon != null) {
        timer.cancel();
        return;
      }

      final index = _activeThreats.indexWhere((threat) => threat.id == d.id);
      if (index != -1) {
        if (DateTime.now().isAfter(expiry)) {
          timer.cancel();
          _activeThreats.removeAt(index);
          NotificationService.showNotification(
            "ASPIRATION DU PORTAIL",
            "Le temps de grâce est écoulé. Le Système vous jette dans le donjon !",
            type: 'dungeon',
          );
          enterDungeon(d.rank, isThreat: true, threatInstance: d, isRed: isRed);
        }
      } else {
        timer.cancel();
      }
    });
  }

  void testUrgentQuestWithDelay() {
    Timer(const Duration(seconds: 5), () => debugTriggerRankedQuest());
  }

  void testDungeonWithDelay() {
    Timer(const Duration(seconds: 5), () => debugForceSpawnThreat(isRed: true));
  }

  void startClassChange() {
    if (_isClassChangeStarted) return;
    _isClassChangeStarted = true;

    final int hours = (_rank == "NATION") ? 72 : 48;
    _classChangeEndTime = DateTime.now().add(Duration(hours: hours));

    _classChangeKm = 0;
    _classChangePompes = 0;
    _classChangeAbdos = 0;
    _classChangeSquats = 0;

    _saveNow();
    _notify();
  }

  void completeClassChange() {
    final bool isMonarchTarget = _rank == "NATION";
    final String targetRank = isMonarchTarget ? "MONARQUE" : "NATION";

    _rank = targetRank;
    _xp = Balance.of(targetRank).xpFloor;
    _syncStatsToRank();

    _isClassChangeStarted = false;
    _classChangeEndTime = null;

    _checkTitles(silent: true);
    _equippedTitle = isMonarchTarget ? "Monarque des Ombres" : "Autorité Nationale";
    _lastRankUp = targetRank;
    _showLevelUpOverlay = true;

    AudioService.playNationGoal();
    NotificationService.showNotification(
      isMonarchTarget ? "ÉVEIL DU MONARQUE" : "ÉVEIL NATIONAL",
      isMonarchTarget
          ? "Saluez le Monarque des Ombres, $_username."
          : "L'humanité vous regarde, $_username.",
      type: 'levelup',
    );

    _saveNow();
    _notify();
  }

  void applyFailurePenalty() {
    _loseXp(Balance.classChangeFailPenalty);
    _coins = (_coins / 2).round();
    _isClassChangeStarted = false;
    _classChangeEndTime = null;
    _classChangeKm = 0;
    _classChangePompes = 0;
    _classChangeAbdos = 0;
    _classChangeSquats = 0;
    _currentHp = _maxHp;
    AudioService.playVictory();
    _saveNow();
    _notify();
  }

  void checkAwakeningFailure() {
    if (!_isClassChangeStarted || formattedRemainingTime != "00:00:00") {
      return;
    }

    final bool isMonarchTarget = _rank == "NATION";
    final double targetKm = isMonarchTarget ? 40.0 : goalNationKm;
    final int targetReps = isMonarchTarget ? 400 : goalNationPompes;

    final bool isCompleted = _classChangeKm >= targetKm &&
        _classChangePompes >= targetReps &&
        _classChangeAbdos >= targetReps &&
        _classChangeSquats >= targetReps;

    if (isCompleted) return;

    if (_currentHp != 1) {
      _currentHp = 1;
      NotificationService.showNotification(
        "ÉCHEC CRITIQUE",
        "Le temps imparti pour l'éveil est écoulé. Le Système extrait votre énergie vitale.",
        type: 'penalty',
      );
      AudioService.playDefeat();
      _saveNow();
      _notify();
    }
  }
}