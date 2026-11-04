// lib/providers/game/game_admin.dart

part of '../game_provider.dart';

// Empty by design: no release master password is embedded in the client.
const String kMasterAdminPassword = "";

mixin _AdminLogic on _GameBase {
  bool get isGodMode => _sandbox;

  Future<void> _forceSaveRealDisk() async {
    // Never disable the global real-save guard to write Sandbox data.
    if (_sandbox) {
      if (_godModePersistPenalty && SandboxManager.persistPenalty) {
        await SandboxManager.saveSandbox(_toJson());
      }
      return;
    }
    await StorageService.save(_toJson());
  }


  /// Activation Pro exclusivement validée par le serveur.
  Future<bool> activateProKey(String rawKey) async {
    final String cleanKey = rawKey.trim().toUpperCase();
    if (cleanKey.isEmpty) return false;
    if (cleanKey == "FREE" || cleanKey == "RESET-PRO") {
      revokePro();
      return false;
    }
    try {
      final deviceId = await _getUniqueHardwareId();
      final activatedKey = await ArenaBackendService.activateProLicense(
        key: cleanKey,
        deviceId: deviceId,
      );
      if (activatedKey == null || activatedKey.isEmpty) return false;
      _isPro = true;
      if (this is GameProvider) {
        await (this as GameProvider).saveLicenseLocally(activatedKey);
      }
      _notify();
      await _forceSaveRealDisk();
      return true;
    } catch (error, stack) {
      debugPrint('[PRO] Activation serveur refusée : $error\\n$stack');
      return false;
    }
  }

  Future<String?> restoreProLicenseByEmail(String emailInput) async {
    final email = emailInput.trim().toLowerCase();
    if (email.isEmpty ||
        !await AuthRecoveryService.hasVerifiedSessionForEmail(email)) {
      return null;
    }
    try {
      final deviceId = await _getUniqueHardwareId();
      final key = await ArenaBackendService.restoreProLicense(
        email: email,
        deviceId: deviceId,
      );
      if (key == null || key.isEmpty) return null;
      _isPro = true;
      if (this is GameProvider) await (this as GameProvider).saveLicenseLocally(key);
      _notify();
      await _forceSaveRealDisk();
      return key;
    } catch (error) {
      debugPrint('[PRO] Restauration serveur refusée : $error');
      return null;
    }
  }

  Future<bool> sendRecoveryEmail(String emailInput) async {
    final email = emailInput.trim().toLowerCase();
    if (email.isEmpty) return false;
    return AuthRecoveryService.sendOfficialRecoveryEmail(email);
  }

  Future<String?> restoreProAfterVerifiedSignIn({
    required String emailInput,
  }) async {
    return restoreProLicenseByEmail(emailInput);
  }

  /// Dialogue modal complet avec le texte neutre "Lancer la vérification"
  Future<void> showOtpRecoveryDialog(BuildContext context) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool verificationLaunched = false;
    bool isLoading = false;
    String feedback = "";

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
                  Icon(Icons.shield_outlined, color: Color(0xFF00E5FF)),
                  SizedBox(width: 10),
                  Text(
                    "RÉCUPÉRATION COMPTE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      verificationLaunched
                          ? "Réinitialisez le mot de passe depuis le lien reçu, puis saisissez le nouveau mot de passe ci-dessous."
                          : "Entrez l'adresse utilisée lors de votre achat. Un lien officiel de réinitialisation Firebase sera envoyé.",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: emailController,
                      enabled: !verificationLaunched && !isLoading,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "ADRESSE E-MAIL",
                        labelStyle: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                        filled: true,
                        fillColor: Colors.black26,
                        prefixIcon: const Icon(Icons.email, color: Color(0xFF00E5FF), size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    if (verificationLaunched) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        enabled: !isLoading,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "NOUVEAU MOT DE PASSE",
                          labelStyle: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                          filled: true,
                          fillColor: Colors.black26,
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFF00E5FF), size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                    if (feedback.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        feedback,
                        style: TextStyle(
                          color: feedback.contains("SUCCÈS") || feedback.contains("lancée") || feedback.contains("effectuée")
                              ? Colors.greenAccent
                              : Colors.redAccent,
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
                            feedback = "Interrogation de la base Firestore...";
                          });

                          if (!verificationLaunched) {
                            final success = await sendRecoveryEmail(emailController.text);
                            setDialogState(() {
                              isLoading = false;
                              if (success) {
                                verificationLaunched = true;
                                feedback = "Lien envoyé. Réinitialisez le mot de passe, puis saisissez-le ici pour valider le compte.";
                              } else {
                                feedback = "ERREUR : Aucun lien envoyé. Vérifiez l'adresse du compte.";
                              }
                            });
                          } else {
                            final signedIn = await AuthRecoveryService.signInWithPassword(
                              emailController.text,
                              passwordController.text,
                            );
                            final restoredKey = signedIn
                                ? await restoreProAfterVerifiedSignIn(emailInput: emailController.text)
                                : null;
                            setDialogState(() {
                              isLoading = false;
                              if (restoredKey != null) {
                                feedback = "SUCCÈS : Licence réactivée ($restoredKey) !";
                                Future.delayed(const Duration(seconds: 1), () {
                                  Navigator.pop(ctx);
                                });
                              } else {
                                feedback = signedIn
                                    ? "Compte non vérifié ou licence liée à un autre appareil."
                                    : "Connexion refusée. Vérifiez le mot de passe et l'adresse.";
                              }
                            });
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(verificationLaunched ? "VÉRIFIER LE COMPTE CONNECTÉ" : "ENVOYER LE LIEN"),
                ),
              ],
            );
          },
        );
      },
    );
    emailController.dispose();
    passwordController.dispose();
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
    final cleanInput = password.trim();
    const bool matchMaster = false;
    final bool canAccessWithStoredPassword =
        kDebugMode || _rank.toUpperCase() == "MONARQUE";
    final bool matchStored = cleanInput == _adminPassword ||
        cleanInput.toUpperCase() == _adminPassword.toUpperCase();

    // La clé maître doit aussi fonctionner dans une APK Release.
    // Le mot de passe administrateur personnalisé reste réservé au debug/Monarque.
    if (!matchMaster && (!canAccessWithStoredPassword || !matchStored)) {
      debugPrint("[SÉCURITÉ] Accès Bac à Sable refusé.");
      return false;
    }

    if (matchMaster || matchStored) {
      if (!_sandbox) {
        _sandboxSnapshot = _toJson();
        _sandbox = true;
        _godModePersistPenalty = false;
        SandboxManager.enterSandbox();

        NotificationService.showNotification(
          "BAC À SABLE ACTIVÉ",
          "Mode God Mode actif.",
          type: 'penalty',
        );
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
      StorageService.writePenaltyState(
        active: true,
        squatsDone: 0,
        squatsGoal: 100,
      );
      SandboxManager.saveSandbox(_toJson());
    } else {
      StorageService.writePenaltyState(
        active: false,
        squatsDone: 0,
        squatsGoal: 100,
      );
    }

    LockService.lockScreen();
    NotificationService.showNotification(
      "PÉNALITÉ QUOTIDIENNE",
      "Quête non validée à minuit.",
      type: 'penalty',
    );
    _notify();
  }

  void sandboxTriggerDungeonBreak() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 150;

    if (_godModePersistPenalty) {
      StorageService.writePenaltyState(
        active: true,
        squatsDone: 0,
        squatsGoal: 150,
      );
      SandboxManager.saveSandbox(_toJson());
    } else {
      StorageService.writePenaltyState(
        active: false,
        squatsDone: 0,
        squatsGoal: 100,
      );
    }

    LockService.lockScreen();
    NotificationService.showNotification(
      "DONJON ROMPU",
      "Le portail a expiré.",
      type: 'penalty',
    );
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