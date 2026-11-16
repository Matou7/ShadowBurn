// lib/providers/game/game_admin.dart
part of '../game_provider.dart';

const String kMasterAdminPassword = "tricheur";

mixin _AdminLogic on _GameBase {
  // STRICTEMENT INTERDIT EN RELEASE : isGodMode retourne false si kDebugMode est faux
  bool get isGodMode => kDebugMode && _sandbox;

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

  Future<bool> activateProKey(String rawKey) async {
    final String cleanKey = rawKey.trim().toUpperCase();
    if (cleanKey.isEmpty) return false;

    if (cleanKey == "FREE" || cleanKey == "RESET-PRO") {
      revokePro();
      return false;
    }

    try {
      final colRef = FirebaseFirestore.instance.collection('pro_licenses');
      DocumentSnapshot? targetSnap;

      final directSnap = await colRef.doc(cleanKey).get(const GetOptions(source: Source.serverAndCache));
      if (directSnap.exists) {
        targetSnap = directSnap;
      } else {
        final querySnap = await colRef.where('key', isEqualTo: cleanKey).limit(1).get();
        if (querySnap.docs.isNotEmpty) {
          targetSnap = querySnap.docs.first;
        }
      }

      if (targetSnap == null || !targetSnap.exists) {
        return false;
      }

      final data = targetSnap.data() as Map<String, dynamic>? ?? {};
      final String hardwareId = await _getUniqueHardwareId();
      final bool alreadyUsed = data['used'] == true;
      final String boundHardware = (data['used_by'] ?? '').toString();

      if (alreadyUsed && boundHardware.isNotEmpty && boundHardware != hardwareId) {
        return false;
      }

      try {
        await targetSnap.reference.update({
          'used': true,
          'used_at': FieldValue.serverTimestamp(),
          'used_by': hardwareId,
          'user_name': _username,
        });
      } catch (writeErr) {
        debugPrint("[PRO_TRACE] Écriture Firestore ignorée : $writeErr");
      }

      _isPro = true;
      if (this is GameProvider) {
        await (this as GameProvider).saveLicenseLocally(targetSnap.id);
      }

      _notify();
      await _forceSaveRealDisk();
      return true;
    } catch (e) {
      debugPrint("[PRO_TRACE] EXCEPTION CRITIQUE FIRESTORE : $e");
      return false;
    }
  }

  Future<bool> requestHardwareAutoRecovery({String? email, String? proof}) async {
    try {
      final String hardwareId = await _getUniqueHardwareId();
      String? recoveredKey = await AuthRecoveryService.fetchKeyForHardware(hardwareId);

      if ((recoveredKey == null || recoveredKey.isEmpty) &&
          email != null &&
          email.trim().isNotEmpty &&
          proof != null &&
          proof.trim().isNotEmpty) {
        recoveredKey = await AuthRecoveryService.recoverKeySecurely(
          email: email,
          proof: proof,
          newHardwareId: hardwareId,
        );
      }

      if (recoveredKey != null && recoveredKey.isNotEmpty) {
        return await activateProKey(recoveredKey);
      }
      return false;
    } catch (e) {
      debugPrint("[AUTH_TRACE] Erreur lors de la récupération : $e");
      return false;
    }
  }

  Future<void> showOtpRecoveryDialog(BuildContext context) async {
    bool isLoading = false;
    String feedback = "";
    final emailController = TextEditingController();
    final proofController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF121217),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.verified_user, color: Color(0xFF00E5FF)),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      "RESTAURATION SÉCURISÉE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "• Même appareil : cliquez directement sur Restaurer.\n• Nouvel appareil / Réinstallation : entrez votre e-mail Stripe ET votre clé (ou les 4 derniers chiffres de la carte).",
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: "E-mail Stripe (si nouvel appareil)",
                        labelStyle: TextStyle(color: Colors.white38, fontSize: 11),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: proofController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: "Clé Pro OU 4 derniers chiffres carte",
                        labelStyle: TextStyle(color: Colors.white38, fontSize: 11),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                    ),
                    if (feedback.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      Text(
                        feedback,
                        style: TextStyle(
                          color: feedback.contains("SUCCÈS") ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text("ANNULER", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() {
                            isLoading = true;
                            feedback = "Vérification cryptographique...";
                          });

                          final success = await requestHardwareAutoRecovery(
                            email: emailController.text,
                            proof: proofController.text,
                          );

                          setDialogState(() {
                            isLoading = false;
                            if (success) {
                              feedback = "SUCCÈS : Licence vérifiée et transférée !";
                              Future.delayed(const Duration(seconds: 1), () {
                                if (Navigator.canPop(ctx)) {
                                  Navigator.pop(ctx);
                                }
                              });
                            } else {
                              feedback = "REFUSÉ : Vérifiez l'e-mail et la clé (ou 4 chiffres carte).";
                            }
                          });
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text("RESTAURER"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool toggleAdminMode(String password) {
    if (!kDebugMode) return false;

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
      _sandbox = false;
      _sandboxSnapshot = null;
      SandboxManager.exitSandbox(keepChanges: keepChanges, currentData: keepChanges ? _toJson() : null);
      if (!keepChanges && _sandboxSnapshot != null) {
        _applyJson(_sandboxSnapshot!);
      }
      _forceSaveRealDisk();
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
