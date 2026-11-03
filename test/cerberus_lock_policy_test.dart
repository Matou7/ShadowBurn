import 'package:flutter_test/flutter_test.dart';
import 'package:shadowburnv2/core/cerberus_lock_policy.dart';

void main() {
  group('CerberusLockPolicy', () {
    test('an expired but unfinished dungeon remains locked', () {
      final expiry = DateTime(2026, 11, 3, 12);
      final now = DateTime(2026, 11, 3, 15);

      expect(now.isAfter(expiry), isTrue);
      expect(
        CerberusLockPolicy.canReleaseDungeon(allTasksCompleted: false),
        isFalse,
      );
      expect(
        CerberusLockPolicy.shouldKeepLocked(
          activeDungeon: true,
          activePenalty: false,
        ),
        isTrue,
      );
    });

    test('a completed dungeon may release the lock but is late after expiry', () {
      final expiry = DateTime(2026, 11, 3, 12);
      final completedAt = DateTime(2026, 11, 3, 15);

      expect(
        CerberusLockPolicy.canReleaseDungeon(allTasksCompleted: true),
        isTrue,
      );
      expect(
        CerberusLockPolicy.isDungeonOnTime(
          completedAt: completedAt,
          expiresAt: expiry,
        ),
        isFalse,
      );
    });

    test('an active penalty keeps Cerberus locked after restart', () {
      expect(
        CerberusLockPolicy.shouldKeepLocked(
          activeDungeon: false,
          activePenalty: true,
        ),
        isTrue,
      );
    });

    test('no active dungeon or penalty means no persistent lock', () {
      expect(
        CerberusLockPolicy.shouldKeepLocked(
          activeDungeon: false,
          activePenalty: false,
        ),
        isFalse,
      );
    });
  });
}
