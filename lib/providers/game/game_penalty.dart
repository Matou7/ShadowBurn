// lib/providers/game/game_penalty.dart

part of '../game_provider.dart';

mixin _PenaltyLogic on _GameBase {
  bool _isCompletingPenalty = false;
  bool get isPenaltyCompleting => _isCompletingPenalty;

  /// Rétablissement direct des données de pénalité depuis le stockage natif (boot).
  void restorePenaltyState(int squatsDone, int squatsGoal) {
    if (_sandbox && !SandboxManager.persistPenalty) return;

    _isInPenaltyZone = true;
    _penaltySquatsDone = squatsDone;
    _kPenaltyGoal = squatsGoal > 0 ? squatsGoal : 100;
    _notify();
  }

  void triggerDailyPenalty() {
    // SÉCURITÉ ZONE BLANCHE : aucune pénalité ne peut être levée le jour de l'installation
    final String today = _todayKey();
    if (_calendarHistory[today]?['status'] == 'white_zone') {
      return;
    }

    if (_sandbox && !SandboxManager.persistPenalty) {
      _isInPenaltyZone = true;
      _penaltySquatsDone = 0;
      _kPenaltyGoal = 100;
      LockService.lockScreen();
      _notify();
      return;
    }

    if (!_isInPenaltyZone) {
      _isInPenaltyZone = true;
      _penaltySquatsDone = 0;
      _kPenaltyGoal = 100;
    } else {
      _kPenaltyGoal += 100;
    }

    _applyPenaltyLockAndPersist();
  }

  void triggerPenaltyState(String reason) {
    dlog("Pénalité déclenchée : $reason");
    triggerDailyPenalty();
  }

  void sandboxTriggerDailyPenalty() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 100;

    if (SandboxManager.persistPenalty) {
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
      "Quête non validée. Le Système verrouille le Hardware.",
      type: 'penalty',
    );
    _notify();
  }

  void triggerDungeonBreakPenalty() {
    _isInPenaltyZone = true;
    _penaltySquatsDone = 0;
    _kPenaltyGoal = 150;

    if (_sandbox && !SandboxManager.persistPenalty) {
      StorageService.writePenaltyState(
        active: false,
        squatsDone: 0,
        squatsGoal: 100,
      );
      LockService.lockScreen();
      _notify();
      return;
    }

    _applyPenaltyLockAndPersist();
  }

  void _applyPenaltyLockAndPersist() {
    if (_sandbox && !SandboxManager.persistPenalty) {
      unawaited(LockService.lockScreen());
      _notify();
      return;
    }
    unawaited(_persistPenaltyActivation());
  }

  Future<void> _persistPenaltyActivation() async {
    await StorageService.writePenaltyState(
      active: true,
      squatsDone: _penaltySquatsDone,
      squatsGoal: _kPenaltyGoal,
    );

    if (SandboxManager.persistPenalty) {
      await SandboxManager.saveSandbox(_toJson());
    } else {
      await _saveNow();
    }

    await LockService.lockScreen();
    _notify();
  }

  Future<void> _persistPenaltyCompletion() async {
    _isCompletingPenalty = true;
    try {
      if (!(_sandbox && !SandboxManager.persistPenalty)) {
        await StorageService.writePenaltyState(
          active: false,
          squatsDone: 0,
          squatsGoal: 100,
        );
        await _saveNow();
      }

      await LockService.unlockScreen();
      NotificationService.showNotification(
        "PÉNALITÉ PURGÉE",
        "Le Système lève le verrouillage. Reprenez votre entraînement.",
        type: 'levelup',
      );
    } finally {
      _isCompletingPenalty = false;
      _notify();
    }
  }

  void processPenaltySquats(int count) {
    if (!_isInPenaltyZone) return;

    _penaltySquatsDone += count;

    if (_penaltySquatsDone >= _kPenaltyGoal) {
      _isInPenaltyZone = false;
      _penaltySquatsDone = 0;
      _kPenaltyGoal = 100;
      unawaited(_persistPenaltyCompletion());
      return;
    } else {
      if (!(_sandbox && !SandboxManager.persistPenalty)) {
        if (SandboxManager.persistPenalty) {
          StorageService.writePenaltyState(
            active: true,
            squatsDone: _penaltySquatsDone,
            squatsGoal: _kPenaltyGoal,
          );
          SandboxManager.saveSandbox(_toJson());
        } else {
          StorageService.writePenaltyState(
            active: true,
            squatsDone: _penaltySquatsDone,
            squatsGoal: _kPenaltyGoal,
          );
          _saveNow();
        }
      }
    }

    _notify();
  }
}