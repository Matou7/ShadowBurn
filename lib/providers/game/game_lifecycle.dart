part of '../game_provider.dart';

mixin _LifecycleLogic on _GameBase {
  Future<void> initializeGame() async {
    String source = 'none';
    int? baseline;

    try {
      final Map<String, dynamic>? godSave = await SandboxManager.loadSandbox();
      if (godSave != null && godSave['godModePersistPenalty'] == true) {
        _applyJson(godSave);
      } else {
        final LoadedSave? loaded = await StorageService.load();
        if (loaded != null) {
          source = loaded.source;
          _applyJson(loaded.data);
          final dynamic b = loaded.data['stepBaseline'];
          baseline = b is num ? b.toInt() : null;
          _applyPassiveRegen(DateTime.tryParse(asString(loaded.data['savedAt'])));
        }

        _sandbox = false;
        _godModePersistPenalty = false;
        SandboxManager.isSandboxActive = false;
        SandboxManager.persistPenalty = false;
        StorageService.blockAllRealSaves = false;

        if (_activeDungeon != null && _activeDungeon!.isRandomThreat && !_godModePersistPenalty) {
          _activeDungeon = null;
          _isActiveDungeonRed = false;
          _dungeonTimer?.cancel();
          LockService.unlockScreen(force: true);
        }
      }
    } catch (e) {
      dlog("Chargement impossible : $e");
    }

    _syncTitleWithRank();

    if (!_isInPenaltyZone || (_sandbox && !_godModePersistPenalty)) {
      _isInPenaltyZone = false;
      _penaltySquatsDone = 0;
      await SandboxManager.clearNativePenalty();
    }

    _steps.configure(baseline: baseline, onEvent: _onSteps);
    _loaded = true;
    _checkTitles(silent: true);
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    await checkMidnightReset();
    _updateCalendarActivity();
    _syncCycleWithCalendar();

    final DateTime now = DateTime.now();
    if (_activeDungeon != null) {
      LockService.lockScreen();
    } else {
      final expiredThreatIndex = _activeThreats.indexWhere((t) => now.isAfter(t.expiresAt));
      if (expiredThreatIndex != -1) {
        final d = _activeThreats.removeAt(expiredThreatIndex);
        enterDungeon(d.rank, isThreat: true, threatInstance: d, isRed: _isActiveDungeonRed);
      }
    }

    _notify();

    if (!_sandbox) {
      await _saveNow();
    }

    if (source.startsWith('backup')) {
      NotificationService.showNotification(
        "SAUVEGARDE DE SECOURS",
        "La sauvegarde principale était illisible : une copie de secours a été restaurée.",
        type: 'backup',
      );
    }

    final bool granted = await _requestPermissions();
    if (granted) _steps.start();

    // FILTRE ZONE BLANCHE : Ne déclenche le service permanent que si le joueur a dépassé l'intro et n'est pas en zone blanche
    final String today = _todayKey();
    final bool isWhiteZone = _calendarHistory[today]?['status'] == 'white_zone';
    if (!isWhiteZone && _lastResetDateStr != null) {
      _updateOngoingSystem(force: true);
    }

    if (_isInPenaltyZone && (!_sandbox || _godModePersistPenalty)) {
      Future.microtask(() => LockService.lockScreen());
    }
  }

  void _applyPassiveRegen(DateTime? lastSave) {
    if (lastSave == null || _currentHp >= _maxHp) return;
    final int hours = DateTime.now().difference(lastSave).inHours;
    if (hours > 0) {
      _currentHp = (_currentHp + hours * 5).clamp(0, _maxHp).toInt();
    }
  }

  Future<bool> _requestPermissions() async {
    bool activityOk = false;
    try {
      PermissionStatus st = await Permission.activityRecognition.status;
      if (!st.isGranted) st = await Permission.activityRecognition.request();
      activityOk = st.isGranted;
      final PermissionStatus n = await Permission.notification.status;
      if (n.isDenied) await Permission.notification.request();
    } catch (e) {
      dlog("Permissions : $e");
    }
    return activityOk;
  }

  void _tick() {
    checkMidnightReset();
    if (_activeThreats.isNotEmpty) {
      final DateTime now = DateTime.now();
      if (_activeDungeon == null) {
        final expiredIndex = _activeThreats.indexWhere((t) => now.isAfter(t.expiresAt));
        if (expiredIndex != -1) {
          final d = _activeThreats.removeAt(expiredIndex);
          enterDungeon(d.rank, isThreat: true, threatInstance: d, isRed: _isActiveDungeonRed);
          _requestSave();
          _notify();
          return;
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_loaded) return;
    if (state == AppLifecycleState.resumed) {
      checkMidnightReset();
      _steps.restart();
      _updateCalendarActivity();
      _syncCycleWithCalendar();
      _urgent?.checkExpired();

      final DateTime now = DateTime.now();
      if (_activeDungeon != null) {
        if (!now.isBefore(_activeDungeon!.expiresAt)) {
          _finishDungeon(victory: false);
        } else {
          LockService.lockScreen();
        }
      } else {
        final expiredIndex = _activeThreats.indexWhere((t) => now.isAfter(t.expiresAt));
        if (expiredIndex != -1) {
          final d = _activeThreats.removeAt(expiredIndex);
          enterDungeon(d.rank, isThreat: true, threatInstance: d, isRed: _isActiveDungeonRed);
        }
      }

      final String today = _todayKey();
      final bool isWhiteZone = _calendarHistory[today]?['status'] == 'white_zone';
      if (!isWhiteZone && _lastResetDateStr != null) {
        _updateOngoingSystem(force: true);
      }

      if (_isInPenaltyZone && (!_sandbox || _godModePersistPenalty)) {
        LockService.lockScreen();
      }
      _notify();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_sandbox && !_godModePersistPenalty) {
        return;
      }
      _saveNow();
    }
  }
}