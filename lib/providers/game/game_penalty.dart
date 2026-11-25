part of '../game_provider.dart';

mixin _PenaltyLogic on _GameBase {
  bool _isProcessingSquats = false;

  void restorePenaltyState(int squatsDone, int squatsGoal) {
    _isInPenaltyZone = true;
    _penaltySquatsDone = squatsDone;
    _kPenaltyGoal = squatsGoal > 0 ? squatsGoal : 100;
    StorageService.writePenaltyState(
      active: true,
      squatsDone: _penaltySquatsDone,
      squatsGoal: _kPenaltyGoal,
    );
    LockService.lockScreen(force: true);
    _notify();
  }

  @override
  void triggerDailyPenalty() {
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

    StorageService.writePenaltyState(
      active: true,
      squatsDone: 0,
      squatsGoal: 100,
    );

    if (SandboxManager.persistPenalty) {
      SandboxManager.saveSandbox(_toJson());
    }

    LockService.lockScreen(force: true);
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

    _applyPenaltyLockAndPersist();
  }

  void _applyPenaltyLockAndPersist() {
    _isInPenaltyZone = true;

    StorageService.writePenaltyState(
      active: true,
      squatsDone: _penaltySquatsDone,
      squatsGoal: _kPenaltyGoal,
    );

    if (_sandbox && SandboxManager.persistPenalty) {
      SandboxManager.saveSandbox(_toJson());
    } else if (!_sandbox) {
      _saveNow();
    }

    LockService.lockScreen(force: true);
    _notify();
  }

  @override
  void processPenaltySquats(int count) {
    if (_isProcessingSquats) return;
    _isProcessingSquats = true;

    try {
      if (!_isInPenaltyZone) {
        _isInPenaltyZone = true;
      }

      _penaltySquatsDone += count;
      dlog(
          "Squats de pénalité : +$count | Total : $_penaltySquatsDone / $_kPenaltyGoal");

      if (_penaltySquatsDone >= _kPenaltyGoal) {
        _isInPenaltyZone = false;
        _penaltySquatsDone = 0;
        _kPenaltyGoal = 100;

        StorageService.writePenaltyState(
          active: false,
          squatsDone: 0,
          squatsGoal: 100,
        );

        if (!(_sandbox && !SandboxManager.persistPenalty)) {
          _saveNow();
        }

        LockService.unlockScreen(force: true);
        _notify();

        NotificationService.showNotification(
          "PÉNALITÉ PURGÉE",
          "Le Système lève le verrouillage. Reprenez votre entraînement.",
          type: 'levelup',
        );
      } else {
        StorageService.writePenaltyState(
          active: true,
          squatsDone: _penaltySquatsDone,
          squatsGoal: _kPenaltyGoal,
        );

        if (!(_sandbox && !SandboxManager.persistPenalty)) {
          if (SandboxManager.persistPenalty) {
            SandboxManager.saveSandbox(_toJson());
          } else {
            _saveNow();
          }
        }
        LockService.lockScreen(force: true);
        _notify();
      }
    } catch (e) {
      dlog("Erreur critique processPenaltySquats : $e");
    } finally {
      _isProcessingSquats = false;
    }
  }
}