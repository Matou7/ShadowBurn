// lib/providers/game/game_save.dart

part of '../game_provider.dart';

const String _kShadowHmacSalt = "SHADOWBURN_ARCHITECT_CORE_HMAC_SIG_99812";

mixin _SaveLogic on _GameBase {
  @override
  void _requestSave() {
    if (!_loaded) return;
    if (_sandbox && !_godModePersistPenalty) return;

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), () => _saveNow());
  }

  @override
  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    if (!_loaded) return;

    if (_sandbox) {
      if (_godModePersistPenalty) {
        await StorageService.saveGodMode(_toJson());
      }
      return;
    }

    _pruneCalendarHistory();
    await StorageService.save(_toJson());
  }

  void persistGame() {
    _saveNow();
  }

  void _pruneCalendarHistory() {
    final DateTime now = DateTime.now();
    final DateTime cutoff =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 365));
    final List<String> toRemove = [];
    _calendarHistory.forEach((dateKey, value) {
      final DateTime? d = DateTime.tryParse(dateKey);
      if (d == null || d.isBefore(cutoff)) toRemove.add(dateKey);
    });
    for (final k in toRemove) {
      _calendarHistory.remove(k);
    }
  }

  void checkGoldGridReward() {
    final DateTime now = DateTime.now();
    bool allGold = true;
    int checkedDays = 0;

    for (int i = 0; i < 60; i++) {
      final checkDate = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: i));
      final dateKey =
          "${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}";
      final dynamic entry = _calendarHistory[dateKey];
      final String? status = entry is Map ? entry['status']?.toString() : entry?.toString();

      if (status != 'gold') {
        allGold = false;
        break;
      }
      checkedDays++;
    }

    if (allGold && checkedDays >= 60) {
      final String todayKey = _todayKey();
      final dynamic todayEntry = _calendarHistory[todayKey];
      if (todayEntry is Map && todayEntry['goldGridRewarded'] == true) {
        return;
      }

      if (todayEntry is Map) {
        todayEntry['goldGridRewarded'] = true;
      }

      final String? higherRank = Balance.next(_rank);
      if (higherRank != null) {
        _inventoryKeys[higherRank] = (_inventoryKeys[higherRank] ?? 0) + 1;
      }

      _currentHp = _maxHp;

      NotificationService.showNotification(
        "MATRICE SUPRÊME PURIFIÉE",
        "2 mois d'or pur. Le Système vous accorde le Ravitaillement du Monarque : Clé supérieure, PV régénérés et immunité de 24h.",
        type: 'levelup',
      );

      AudioService.playVictory();
      _saveNow();
      _notify();
    }
  }

  @override
  Map<String, dynamic> _toJson() {
    return {
      'v': 4,
      'savedAt': DateTime.now().toIso8601String(),
      'username': _username,
      'rank': _rank,
      'xp': _xp,
      'coins': _coins,
      'hp': _currentHp,
      'maxHp': _maxHp,
      'streak': _streak,
      'lastResetDate': _lastResetDateStr,
      'keys': _inventoryKeys,
      'isPro': _isPro,
      'unlockedTitles': _unlockedTitles,
      'equippedTitle': _equippedTitle,
      'pompes': _pompes,
      'abdos': _abdos,
      'squats': _squats,
      'steps': _dailySteps,
      'sessionKm': _sessionKm,
      'dailyKm': _dailyKm,
      'cycles': _dailyCyclesCompleted,
      'recordBrokenToday': _recordBrokenToday,
      'isTracking': _isTracking,
      'totalPompes': _totalPompes,
      'totalAbdos': _totalAbdos,
      'totalSquats': _totalSquats,
      'totalKm': _totalKm,
      'totalSurpassement': _totalSurpassement,
      'dungeonsCompleted': _dungeonsCompleted,
      'maxPompes': _maxPompes,
      'maxAbdos': _maxAbdos,
      'maxSquats': _maxSquats,
      'maxKm': _maxKm,
      'penaltyActive': _isInPenaltyZone,
      'penaltySquats': _penaltySquatsDone,
      'penaltyGoal': _kPenaltyGoal,
      'sandbox': _sandbox,
      'sandboxSnapshot': _sandboxSnapshot,
      'godModePersistPenalty': _godModePersistPenalty,
      'cc': {
        'started': _isClassChangeStarted,
        'end': _classChangeEndTime?.toIso8601String(),
        'p': _classChangePompes,
        'a': _classChangeAbdos,
        's': _classChangeSquats,
        'k': _classChangeKm,
      },
      'calendar': _calendarHistory,
      'saveHistory': _saveHistory,
      'dungeon': _activeDungeon?.toJson(),
      'dungeonRed': _isActiveDungeonRed,
      'threats': _activeThreats.map((t) => t.toJson()).toList(),
      'urgent': _urgent?.toJson(),
      'surpassQuest': _isSurpassQuest,
      'adminPassword': _adminPassword,
      'stepBaseline': _steps.baseline,
    };
  }

  @override
  void _applyJson(Map<String, dynamic> j) {
    _username = asString(j['username'], "Chasseur");
    final String r = asString(j['rank'], "E");
    _rank = Balance.order.contains(r) ? r : "E";
    _xp = max(0.0, asDouble(j['xp']));
    _coins = max(0, asInt(j['coins']));
    _maxHp = max(1, asInt(j['maxHp'], 100));
    _currentHp = asInt(j['hp'], 100).clamp(0, _maxHp);
    _streak = max(0, asInt(j['streak']));
    _currentStreak = _streak;
    final dynamic lr = j['lastResetDate'];
    _lastResetDateStr = (lr is String && lr.isNotEmpty) ? lr : null;

    _inventoryKeys = {"E": 0, "D": 0, "C": 0, "B": 0, "A": 0, "S": 0, "NATION": 0};
    asMap(j['keys']).forEach((k, v) => _inventoryKeys[k] = max(0, asInt(v)));

    _isPro = asBool(j['isPro']);

    _unlockedTitles = asList(j['unlockedTitles']).whereType<String>().toList();
    if (!_unlockedTitles.contains(Titles.defaultTitle)) {
      _unlockedTitles.insert(0, Titles.defaultTitle);
    }
    _equippedTitle = asString(j['equippedTitle'], Titles.defaultTitle);
    if (!_unlockedTitles.contains(_equippedTitle)) {
      _equippedTitle = Titles.defaultTitle;
    }

    _pompes = max(0, asInt(j['pompes']));
    _abdos = max(0, asInt(j['abdos']));
    _squats = max(0, asInt(j['squats']));
    _dailySteps = max(0, asInt(j['steps']));
    _sessionKm = max(0.0, asDouble(j['sessionKm']));

    if (j.containsKey('dailyKm')) {
      _dailyKm = max(0.0, asDouble(j['dailyKm']));
    } else {
      _dailyKm = 0.0;
    }

    _dailyCyclesCompleted = max(0, asInt(j['cycles']));
    _recordBrokenToday = asBool(j['recordBrokenToday']);
    _isTracking = asBool(j['isTracking']);

    _totalPompes = max(0, asInt(j['totalPompes']));
    _totalAbdos = max(0, asInt(j['totalAbdos']));
    _totalSquats = max(0, asInt(j['totalSquats']));

    final double rawTotalKm = max(0.0, asDouble(j['totalKm']));
    if (rawTotalKm == 100.0 && _totalPompes == 0 && _totalAbdos == 0 && _totalSquats == 0 && _dailySteps == 0) {
      _totalKm = 0.0;
    } else {
      _totalKm = rawTotalKm;
    }

    _totalSurpassement = max(0, asInt(j['totalSurpassement']));
    _dungeonsCompleted = max(0, asInt(j['dungeonsCompleted']));
    _maxPompes = max(0, asInt(j['maxPompes']));
    _maxAbdos = max(0, asInt(j['maxAbdos']));
    _maxSquats = max(0, asInt(j['maxSquats']));
    _maxKm = max(0.0, asDouble(j['maxKm']));

    _isInPenaltyZone = asBool(j['penaltyActive']);
    _penaltySquatsDone = max(0, asInt(j['penaltySquats']));
    _kPenaltyGoal = max(1, asInt(j['penaltyGoal'], 100));

    _godModePersistPenalty = asBool(j['godModePersistPenalty']);
    _sandbox = asBool(j['sandbox']);
    final dynamic snap = j['sandboxSnapshot'];
    _sandboxSnapshot = snap is Map ? Map<String, dynamic>.from(snap) : null;

    final cc = asMap(j['cc']);
    final dynamic end = cc['end'];
    _classChangeEndTime = end is String ? DateTime.tryParse(end) : null;
    _isClassChangeStarted = asBool(cc['started']) && _classChangeEndTime != null;
    _classChangePompes = max(0, asInt(cc['p']));
    _classChangeAbdos = max(0, asInt(cc['a']));
    _classChangeSquats = max(0, asInt(cc['s']));
    _classChangeKm = max(0.0, asDouble(cc['k']));

    _calendarHistory = asMap(j['calendar']);
    _saveHistory = asList(j['saveHistory']).map((e) => asMap(e)).toList();

    _dungeonTimer?.cancel();
    _activeDungeon = null;
    final dynamic dj = j['dungeon'];
    if (dj is Map) {
      try {
        _activeDungeon = Dungeon.fromJson(Map<String, dynamic>.from(dj));
      } catch (e) {
        dlog("Donjon illisible : $e");
      }
    }
    _isActiveDungeonRed = _activeDungeon != null && asBool(j['dungeonRed']);
    _warningGiven = false;

    final DateTime nowT = DateTime.now();
    _activeThreats = [];
    for (final t in asList(j['threats'])) {
      try {
        final d = Dungeon.fromJson(asMap(t));
        if (d.expiresAt.isAfter(nowT)) _activeThreats.add(d);
      } catch (_) {}
    }

    _isSurpassQuest = asBool(j['surpassQuest']);

    final String loadedPwd = asString(j['adminPassword'], kMasterAdminPassword);
    _adminPassword = loadedPwd.trim().isNotEmpty ? loadedPwd.trim() : kMasterAdminPassword;

    final dynamic urgentJson = j['urgent'];
    if (_urgent != null) {
      if (urgentJson is Map) {
        _urgent!.restore(Map<String, dynamic>.from(urgentJson));
        _urgent!.checkExpired();
      } else if (_urgent!.isActive) {
        _urgent!.resetStatus();
      }
    } else {
      _pendingUrgentJson = urgentJson is Map ? Map<String, dynamic>.from(urgentJson) : null;
    }

    _syncStatsToRank();
    if (_activeDungeon != null) _startDungeonTimer();

    if (_isInPenaltyZone || _activeDungeon != null) {
      Future.microtask(() => LockService.lockScreen());
    }
  }

  /// Algorithme de hachage double canal FNV-1a 32-bit + DJB2 32-bit
  /// 100 % compatible Web (dart2js 53-bit max) et Natif Android/Windows
  String _generateSaveSignature(String payload) {
    int hash1 = 0x811c9dc5;
    int hash2 = 0x1505;
    final bytes = utf8.encode(payload + _kShadowHmacSalt);
    for (final b in bytes) {
      hash1 ^= b;
      hash1 = (hash1 * 0x01000193) & 0xFFFFFFFF;
      hash2 = ((hash2 * 33) ^ b) & 0xFFFFFFFF;
    }
    final String h1 = hash1.toRadixString(16).padLeft(8, '0');
    final String h2 = hash2.toRadixString(16).padLeft(8, '0');
    return "$h1$h2";
  }

  String exportSaveCode() {
    final Map<String, dynamic> data = _toJson();
    final String jsonString = jsonEncode(data);
    final String base64Payload = base64Encode(utf8.encode(jsonString));
    final String signature = _generateSaveSignature(base64Payload);
    final String signedCode = "$base64Payload.$signature";

    addToHistory(signedCode);
    return signedCode;
  }

  void addToHistory(String code) {
    final Map<String, dynamic> entry = {
      'date': DateTime.now().toIso8601String(),
      'code': code,
      'rank': _rank,
      'xp': _xp,
      'username': _username,
    };
    _saveHistory.insert(0, entry);
    if (_saveHistory.length > 3) _saveHistory.removeLast();
    _requestSave();
    _notify();
  }

  Future<bool> importSaveCode(String rawCode) async {
    try {
      final String trimmed = rawCode.trim();
      String payload = trimmed;

      if (trimmed.contains('.')) {
        final parts = trimmed.split('.');
        if (parts.length == 2) {
          final String body = parts[0];
          final String providedSig = parts[1];
          final String expectedSig = _generateSaveSignature(body);

          if (providedSig != expectedSig) {
            dlog("[SÉCURITÉ] Rejet Import : Empreinte de signature invalide (Sauvegarde corrompue ou falsifiée).");
            return false;
          }
          payload = body;
        } else {
          return false;
        }
      } else {
        dlog("[SÉCURITÉ] Sauvegarde non signée : Format non certifié.");
      }

      final String jsonString = utf8.decode(base64Decode(payload));
      final Map<String, dynamic> data = asMap(jsonDecode(jsonString));
      await StorageService.backupNow();
      _applyJson(data);
      await _saveNow();
      _updateOngoingSystem(force: true);
      _notify();
      return true;
    } catch (e) {
      dlog("Erreur Import: $e");
      return false;
    }
  }
}