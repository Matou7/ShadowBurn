// lib/providers/game/game_admin.dart
part of '../game_provider.dart';

const String kMasterAdminPassword = "tricheur";

mixin _AdminLogic on _GameBase {
  @override
  bool get isGodMode => kDebugMode && _sandbox;

  Map<String, dynamic>? _cloneSnapshot(Map<String, dynamic>? source) {
    if (source == null) return null;
    try {
      final decoded = jsonDecode(jsonEncode(source));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return Map<String, dynamic>.from(source);
  }

  Future<void> _forceSaveRealDisk() async {
    final bool wasBlocked = StorageService.blockAllRealSaves;
    StorageService.blockAllRealSaves = false;
    try {
      final data = _toJson();
      data['sandbox'] = false;
      data['sandboxSnapshot'] = null;
      data['godModePersistPenalty'] = false;
      await StorageService.save(data);
    } finally {
      StorageService.blockAllRealSaves = wasBlocked;
    }
  }

  void _persistIfNotSandbox() {
    if (_sandbox) return;
    unawaited(_forceSaveRealDisk());
  }

  Future<String> getUniqueHardwareIdForCheckout() async {
    return await _getUniqueHardwareId();
  }

  Future<String> useEmergencyAmnesty() async {
    if (!_isInPenaltyZone && _activeDungeon == null) {
      return "AUCUNE ANOMALIE DÉTECTÉE : Vous n'êtes actuellement soumis à aucune pénalité ou blocage.";
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final int lastUsedMs = prefs.getInt('shadow_last_amnesty_ms') ?? 0;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      const int thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;

      if (!_sandbox && lastUsedMs > 0 && (nowMs - lastUsedMs) < thirtyDaysMs) {
        final int daysLeft =
            ((thirtyDaysMs - (nowMs - lastUsedMs)) / (1000 * 60 * 60 * 24))
                .ceil();
        return "RECOURS REFUSÉ : Le Jeton d'Amnistie est en cours de régénération ($daysLeft jours restants).";
      }

      _isInPenaltyZone = false;
      _penaltySquatsDone = 0;
      _activeDungeon = null;
      _dungeonTimer?.cancel();

      await StorageService.writePenaltyState(
          active: false, squatsDone: 0, squatsGoal: 100);
      await SandboxManager.clearNativePenalty();
      try {
        await LockService.unlockScreen();
      } catch (_) {}

      if (!_sandbox) {
        await prefs.setInt('shadow_last_amnesty_ms', nowMs);
        await _forceSaveRealDisk();
      }

      _notify();

      return _sandbox
          ? "AMNISTIE SYSTÈME ACCORDÉE (GOD MODE) : Blocage levé immédiatement."
          : "AMNISTIE SYSTÈME ACCORDÉE : Pénalité levée. Prochain recours disponible dans 30 jours.";
    } catch (e) {
      return "Erreur lors de l'exécution du protocole : $e";
    }
  }

  Future<bool> activateProKey(String rawKey) async {
    if (this is GameProvider) {
      return await (this as GameProvider).activateProKey(rawKey);
    }
    return false;
  }

  Future<bool> requestHardwareAutoRecovery(
      {String? email, String? proof}) async {
    if (this is GameProvider) {
      return await (this as GameProvider).requestHardwareAutoRecovery(
        email: email,
        proof: proof,
      );
    }
    return false;
  }

  Future<void> showOtpRecoveryDialog(BuildContext context) async {
    if (this is GameProvider) {
      await (this as GameProvider).showOtpRecoveryDialog(context);
    }
  }

  bool toggleAdminMode(String password) {
    if (!kDebugMode) return false;

    final cleanInput = password.trim();
    final bool matchMaster =
        cleanInput.toUpperCase() == kMasterAdminPassword.toUpperCase();
    final bool matchStored = cleanInput == _adminPassword ||
        cleanInput.toUpperCase() == _adminPassword.toUpperCase();

    if (matchMaster || matchStored) {
      _adminPassword = kMasterAdminPassword;
      if (!_sandbox) {
        final rawSnapshot = _toJson();
        rawSnapshot['sandbox'] = false;
        rawSnapshot['sandboxSnapshot'] = null;
        rawSnapshot['godModePersistPenalty'] = false;
        _sandboxSnapshot = _cloneSnapshot(rawSnapshot);
        _sandbox = true;
        _godModePersistPenalty = false;
        SandboxManager.enterSandbox();
      }
      _notify();
      return true;
    }
    return false;
  }

  Future<void> toggleGodModePersistPenalty() async {
    if (!kDebugMode) return;
    _godModePersistPenalty = !_godModePersistPenalty;
    SandboxManager.persistPenalty = _godModePersistPenalty;

    if (!_godModePersistPenalty) {
      await SandboxManager.deleteSandboxFile();
      await SandboxManager.clearNativePenalty();
    } else {
      if (_isInPenaltyZone) {
        await StorageService.writePenaltyState(
          active: true,
          squatsDone: _penaltySquatsDone,
          squatsGoal: _kPenaltyGoal,
        );
      }
      await SandboxManager.saveSandbox(_toJson());
    }

    _notify();
  }

  Future<void> _finalizeExitGodMode({required bool keepChanges}) async {
    if (!_sandbox) return;

    final Map<String, dynamic>? savedSnapshot = _cloneSnapshot(_sandboxSnapshot);
    final Map<String, dynamic>? currentSnapshot =
        keepChanges ? _cloneSnapshot(_toJson()) : null;

    _sandbox = false;
    _sandboxSnapshot = null;
    _godModePersistPenalty = false;

    if (!keepChanges && savedSnapshot != null) {
      _applyJson(savedSnapshot);
    }

    await SandboxManager.exitSandbox(
      keepChanges: keepChanges,
      currentData: currentSnapshot,
      snapshotData: savedSnapshot,
    );

    if (!keepChanges && savedSnapshot != null) {
      _applyJson(savedSnapshot);
    }

    _notify();
  }

  void exitGodMode({required bool keepChanges}) {
    if (!_sandbox) return;
    unawaited(_finalizeExitGodMode(keepChanges: keepChanges));
  }

  void setAdminPassword(String newPassword) {
    if (newPassword.trim().isNotEmpty) {
      _adminPassword = newPassword.trim();
      _persistIfNotSandbox();
      _notify();
    }
  }

  void setGoldCoins(int amount) {
    _coins = max(0, amount);
    _persistIfNotSandbox();
    _notify();
  }

  void adminAddCoins(int amount) {
    _coins = max(0, _coins + amount);
    _persistIfNotSandbox();
    _notify();
  }

  void adminAddXp(double amount) {
    _xp += amount;
    _checkRankUp();
    _persistIfNotSandbox();
    _notify();
  }

  void adminHeal() {
    _currentHp = _maxHp;
    _persistIfNotSandbox();
    _notify();
  }

  void setTotalSurpass(int val) {
    _totalSurpassement = max(0, val);
    _checkTitles(silent: true);
    _persistIfNotSandbox();
    _notify();
  }

  void setDailyStat(String statKey, num value) {
    final int valInt = value.toInt();
    final k = statKey.toLowerCase();
    if (k.contains("pompe")) {
      _pompes = max(0, valInt);
    } else if (k.contains("abdo")) {
      _abdos = max(0, valInt);
    } else if (k.contains("squat")) {
      _squats = max(0, valInt);
    }
    _updateCalendarActivity();
    _checkCycleCompletion();
    _checkDungeonStatus();
    _checkTitles(silent: true);
    _persistIfNotSandbox();
    _notify();
  }

  void setDailyKm(double km) {
    _dailyKm = max(0.0, km);
    _dailySteps = ((_dailyKm * 1000.0) / 0.75).round();
    _updateCalendarActivity();
    _checkCycleCompletion();
    _checkTitles(silent: true);
    _persistIfNotSandbox();
    _notify();
  }

  void setDailySteps(int steps) {
    _dailySteps = max(0, steps);
    _dailyKm = (_dailySteps * 0.75) / 1000.0;
    _updateCalendarActivity();
    _checkCycleCompletion();
    _checkTitles(silent: true);
    _persistIfNotSandbox();
    _notify();
  }

  void setDungeonKey(String rank, int qty) {
    _inventoryKeys[rank] = max(0, qty);
    _persistIfNotSandbox();
    _notify();
  }

  void updateTotalStat(String label, num val) {
    final int valInt = val.toInt();
    final l = label.toLowerCase();
    if (l.contains("pompe")) {
      _totalPompes = max(0, valInt);
    } else if (l.contains("abdo")) {
      _totalAbdos = max(0, valInt);
    } else if (l.contains("squat")) {
      _totalSquats = max(0, valInt);
    } else if (l.contains("endurance") || l.contains("km")) {
      _totalKm = max(0.0, val.toDouble());
    } else if (l.contains("discipline") || l.contains("streak")) {
      _currentStreak = max(0, valInt);
      _streak = max(0, valInt);
    } else if (l.contains("surpass")) {
      _totalSurpassement = max(0, valInt);
    }
    _checkTitles(silent: true);
    _persistIfNotSandbox();
    _notify();
  }

  void deleteHistoryEntry(String dateKey) {
    _calendarHistory.remove(dateKey);
    if (dateKey == _todayKey()) {
      _dailyCyclesCompleted = 0;
    }
    _persistIfNotSandbox();
    _notify();
  }

  void updateHistoryStatus(String dateKey, String status) {
    if (_calendarHistory[dateKey] != null) {
      (_calendarHistory[dateKey] as Map)['status'] = status;
    } else {
      _calendarHistory[dateKey] = {'status': status, 'recordBroken': false};
    }

    if (dateKey == _todayKey()) {
      if (status != 'gold') {
        _dailyCyclesCompleted = 0;
      } else if (_dailyCyclesCompleted == 0) {
        _dailyCyclesCompleted = 1;
      }
    }

    _persistIfNotSandbox();
    _notify();
  }

  void sandboxTriggerDailyPenalty() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 100;

    if (_godModePersistPenalty) {
      StorageService.writePenaltyState(
          active: true, squatsDone: 0, squatsGoal: 100);
      SandboxManager.saveSandbox(_toJson());
    } else {
      StorageService.writePenaltyState(
          active: false, squatsDone: 0, squatsGoal: 100);
    }

    LockService.lockScreen();
    NotificationService.showNotification(
        "PÉNALITÉ QUOTIDIENNE", "Quête non validée à minuit.",
        type: 'penalty');
    _notify();
  }

  void sandboxTriggerDungeonBreak() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 150;

    LockService.lockScreen();
    NotificationService.showNotification(
        "DONJON ROMPU", "Le portail a expiré.",
        type: 'penalty');
    _notify();
  }

  void sandboxClearPenalty() {
    _isInPenaltyZone = false;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 100;
    SandboxManager.deleteSandboxFile();
    SandboxManager.clearNativePenalty();
    _notify();
  }
}