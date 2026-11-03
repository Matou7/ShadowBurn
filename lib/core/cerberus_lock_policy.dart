/// Central rules for Cerberus lock release.
///
/// A deadline changes the dungeon result, never the lock state.
/// Only completing every required task may release a dungeon.
class CerberusLockPolicy {
  const CerberusLockPolicy._();

  static bool canReleaseDungeon({required bool allTasksCompleted}) {
    return allTasksCompleted;
  }

  static bool isDungeonOnTime({
    required DateTime completedAt,
    required DateTime expiresAt,
  }) {
    return completedAt.isBefore(expiresAt);
  }

  static bool shouldKeepLocked({
    required bool activeDungeon,
    required bool activePenalty,
  }) {
    return activeDungeon || activePenalty;
  }
}
