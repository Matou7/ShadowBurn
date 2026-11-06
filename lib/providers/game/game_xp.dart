// lib/providers/game/game_xp.dart
part of '../game_provider.dart';

mixin _XpLogic on _GameBase {
  @override
  void _checkRankUp() {
    final String? nextRank = Balance.next(_rank);
    if (nextRank == null) return;

    if (_rank == "S" && nextRank == "NATION") {
      if (_xp >= Balance.classChangeNationXp && !_isClassChangeStarted) {
        // En attente de l'épreuve de classe
      }
      return;
    }

    if (_rank == "NATION" && nextRank == "MONARQUE") {
      if (_xp >= Balance.classChangeMonarqueXp && !_isClassChangeStarted) {
        // En attente de l'épreuve Monarque
      }
      return;
    }

    if (_xp >= _cfg.xpNext) {
      _rank = nextRank;
      _lastRankUp = nextRank;
      _showLevelUpOverlay = true;
      _syncStatsToRank();
      _syncTitleWithRank();
      AudioService.playLevelUp();
      NotificationService.showNotification(
        "MONTÉE EN RANG !",
        "Félicitations $_username, vous atteignez le rang $nextRank ($_equippedTitle).",
        type: 'levelup',
      );
      _checkTitles(silent: true);
      _requestSave();
      _notify();
    }
  }

  @override
  void _loseXp(num amount) {
    _xp = max(_cfg.xpFloor, _xp - amount.toDouble());
    _requestSave();
    _notify();
  }

  void addXp(double amount) {
    _xp += amount;
    _checkRankUp();
    _requestSave();
    _notify();
  }
}