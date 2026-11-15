// lib/providers/game/game_admin.dart
part of '../game_provider.dart';

const String kMasterAdminPassword = "tricheur";

mixin _AdminLogic on _GameBase {
  bool get isGodMode => _sandbox;

  Future<void> _forceSaveRealDisk() async {
    final bool wasBlocked = StorageService.blockAllRealSaves;
    StorageService.blockAllRealSaves = false;
    final data = _toJson();
    data['sandbox'] = false;
    await StorageService.save(data);
    if (_sandbox) {
      _sandboxSnapshot = Map<String, dynamic>.from(data);
    }
    StorageService.blockAllRealSaves = wasBlocked;
  }

  /// Protocole d'Amnistie
  Future<String> useEmergencyAmnistie() async {
    if (!_isInPenaltyZone && _activeDungeon == null) {
      return "AUCUNE ANOMALIE DÉTECTÉE : Vous n'êtes actuellement soumis à aucune pénalité ou blocage.";
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final int lastUsedMs = prefs.getInt('shadow_last_amnesty_ms') ?? 0;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      const int thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;

      if (!_sandbox && lastUsedMs > 0 && (nowMs - lastUsedMs) < thirtyDaysMs) {
        final int daysLeft = ((thirtyDaysMs - (nowMs - lastUsedMs)) / (1000 * 60 * 60 * 24)).ceil();
        return "RECOURS REFUSÉ : Le Jeton d'Amnistie est en cours de régénération ($daysLeft jours restants).";
      }

      _isInPenaltyZone = false;
      _penaltySquatsDone = 0;
      _activeDungeon = null;
      _dungeonTimer?.cancel();

      await StorageService.writePenaltyState(active: false, squatsDone: 0, squatsGoal: 100);
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

  /// Active une clé de licence Pro Monarque de façon robuste et directe
  Future<bool> activateProKey(String rawKey) async {
    final String cleanKey = rawKey.trim().toUpperCase();
    debugPrint("[PRO_TRACE] Début activation clé : '$cleanKey'");

    if (cleanKey.isEmpty) {
      debugPrint("[PRO_TRACE] Échec : Clé vide.");
      return false;
    }

    if (cleanKey == "FREE" || cleanKey == "RESET-PRO") {
      revokePro();
      debugPrint("[PRO_TRACE] Révocation effectuée.");
      return false;
    }

    try {
      final colRef = FirebaseFirestore.instance.collection('pro_licenses');
      DocumentReference? targetDocRef;

      final directDocRef = colRef.doc(cleanKey);
      final directSnap = await directDocRef.get(const GetOptions(source: Source.serverAndCache));

      if (directSnap.exists) {
        targetDocRef = directDocRef;
      } else {
        final querySnap = await colRef.where('key', isEqualTo: cleanKey).limit(1).get();
        if (querySnap.docs.isNotEmpty) {
          targetDocRef = querySnap.docs.first.reference;
        } else {
          return false;
        }
      }

      final String hardwareId = await _getUniqueHardwareId();

      await targetDocRef.update({
        'used': true,
        'used_at': FieldValue.serverTimestamp(),
        'used_by': hardwareId,
        'user_name': _username,
      });

      _isPro = true;
      if (this is GameProvider) {
        await (this as GameProvider).saveLicenseLocally(targetDocRef.id);
      }

      _notify();
      await _forceSaveRealDisk();
      return true;
    } catch (e, stack) {
      debugPrint("[PRO_TRACE] EXCEPTION CRITIQUE FIRESTORE : $e\n$stack");
      return false;
    }
  }

  /// Restauration automatique par ID Matériel
  Future<bool> requestHardwareAutoRecovery() async {
    try {
      final String hardwareId = await _getUniqueHardwareId();
      final String? recoveredKey = await AuthRecoveryService.fetchKeyForHardware(hardwareId);
      
      if (recoveredKey != null && recoveredKey.isNotEmpty) {
        final bool success = await activateProKey(recoveredKey);
        return success;
      } else {
        return false;
      }
    } catch (e, stack) {
      debugPrint("[AUTH_TRACE] Erreur lors de la récupération matérielle : $e\n$stack");
      return false;
    }
  }

  Future<void> toggleGodModePersistPenalty() async {
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

  void clearPenaltyIfNoPersistence() {
    if (_sandbox && !_godModePersistPenalty) {
      if (_sandboxSnapshot != null) {
        _applyJson(_sandboxSnapshot!);
      }
      _sandbox = false;
      _sandboxSnapshot = null;
      _activeDungeon = null;
      _isInPenaltyZone = false;
      _penaltySquatsDone = 0;
      SandboxManager.exitSandbox(keepChanges: false);
    }
  }

  bool toggleAdminMode(String password) {
    final bool canAccess = kDebugMode || _rank.toUpperCase() == "MONARQUE";
    if (!canAccess) return false;

    final cleanInput = password.trim();
    final bool matchMaster = cleanInput.toUpperCase() == kMasterAdminPassword.toUpperCase();
    final bool matchStored = cleanInput == _adminPassword || cleanInput.toUpperCase() == _adminPassword.toUpperCase();

    if (matchMaster || matchStored) {
      _adminPassword = kMasterAdminPassword;
      if (!_sandbox) {
        _sandboxSnapshot = _toJson();
        _sandbox = true;
        _godModePersistPenalty = false;
        SandboxManager.enterSandbox();
      }
      _forceSaveRealDisk();
      _notify();
      return true;
    }
    return false;
  }

  void exitGodMode({required bool keepChanges}) {
    if (_sandbox) {
      if (keepChanges) {
        _sandbox = false;
        _sandboxSnapshot = null;
        SandboxManager.exitSandbox(keepChanges: true, currentData: _toJson());
        _saveNow();
      } else {
        if (_sandboxSnapshot != null) {
          _applyJson(_sandboxSnapshot!);
        }
        _sandbox = false;
        _sandboxSnapshot = null;
        SandboxManager.exitSandbox(keepChanges: false);
      }
      _notify();
    }
  }

  void setAdminPassword(String newPassword) {
    if (newPassword.trim().isNotEmpty) {
      _adminPassword = newPassword.trim();
      _forceSaveRealDisk();
      _notify();
    }
  }

  void setGoldCoins(int amount) {
    _coins = max(0, amount);
    _forceSaveRealDisk();
    _notify();
  }

  void adminAddCoins(int amount) {
    _coins = max(0, _coins + amount);
    _forceSaveRealDisk();
    _notify();
  }

  void adminAddXp(double amount) {
    _xp += amount;
    _checkRankUp();
    _forceSaveRealDisk();
    _notify();
  }

  void adminHeal() {
    _currentHp = _maxHp;
    _forceSaveRealDisk();
    _notify();
  }

  void setTotalSurpass(int val) {
    _totalSurpassement = max(0, val);
    _checkTitles(silent: true);
    _forceSaveRealDisk();
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
    _forceSaveRealDisk();
    _notify();
  }

  void setDailyKm(double km) {
    _dailyKm = max(0.0, km);
    _dailySteps = ((_dailyKm * 1000.0) / 0.75).round();
    _updateCalendarActivity();
    _checkCycleCompletion();
    _checkTitles(silent: true);
    _forceSaveRealDisk();
    _notify();
  }

  void setDailySteps(int steps) {
    _dailySteps = max(0, steps);
    _dailyKm = (_dailySteps * 0.75) / 1000.0;
    _updateCalendarActivity();
    _checkCycleCompletion();
    _checkTitles(silent: true);
    _forceSaveRealDisk();
    _notify();
  }

  void setDungeonKey(String rank, int qty) {
    _inventoryKeys[rank] = max(0, qty);
    _forceSaveRealDisk();
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
    _forceSaveRealDisk();
    _notify();
  }

  void deleteHistoryEntry(String dateKey) {
    _calendarHistory.remove(dateKey);
    if (dateKey == _todayKey()) {
      _dailyCyclesCompleted = 0;
    }
    _forceSaveRealDisk();
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

    _forceSaveRealDisk();
    _notify();
  }

  void sandboxTriggerDailyPenalty() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 100;

    if (_godModePersistPenalty) {
      StorageService.writePenaltyState(active: true, squatsDone: 0, squatsGoal: 100);
      SandboxManager.saveSandbox(_toJson());
    } else {
      StorageService.writePenaltyState(active: false, squatsDone: 0, squatsGoal: 100);
    }

    LockService.lockScreen();
    NotificationService.showNotification("PÉNALITÉ QUOTIDIENNE", "Quête non validée à minuit.", type: 'penalty');
    _notify();
  }

  void sandboxTriggerDungeonBreak() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 150;

    if (_godModePersistPenalty) {
      StorageService.writePenaltyState(active: true, squatsDone: 0, squatsGoal: 150);
      SandboxManager.saveSandbox(_toJson());
    } else {
      StorageService.writePenaltyState(active: false, squatsDone: 0, squatsGoal: 100);
    }

    LockService.lockScreen();
    NotificationService.showNotification("DONJON ROMPU", "Le portail a expiré.", type: 'penalty');
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
