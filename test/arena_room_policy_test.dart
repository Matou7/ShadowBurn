import 'package:flutter_test/flutter_test.dart';
import 'package:shadowburnv2/services/arena_room_policy.dart';

void main() {
  group('ArenaRoomPolicy', () {
    test('accepts only room_1 through room_100', () {
      expect(ArenaRoomPolicy.parseRoomNumber('room_1'), 1);
      expect(ArenaRoomPolicy.parseRoomNumber('room_100'), 100);
      expect(ArenaRoomPolicy.parseRoomNumber('room_0'), isNull);
      expect(ArenaRoomPolicy.parseRoomNumber('room_101'), isNull);
      expect(ArenaRoomPolicy.parseRoomNumber('room_01'), isNull);
      expect(ArenaRoomPolicy.parseRoomNumber('room_admin'), isNull);
      expect(ArenaRoomPolicy.parseRoomNumber(null), isNull);
    });

    test('requires a non-empty exact portal token', () {
      expect(
        ArenaRoomPolicy.hasValidJoinToken(
          expectedToken: 'ABCD1234',
          receivedToken: 'abcd1234',
        ),
        isTrue,
      );
      expect(
        ArenaRoomPolicy.hasValidJoinToken(
          expectedToken: '',
          receivedToken: 'abcd1234',
        ),
        isFalse,
      );
      expect(
        ArenaRoomPolicy.hasValidJoinToken(
          expectedToken: 'ABCD1234',
          receivedToken: '',
        ),
        isFalse,
      );
      expect(
        ArenaRoomPolicy.hasValidJoinToken(
          expectedToken: 'ABCD1234',
          receivedToken: 'ABCD1235',
        ),
        isFalse,
      );
    });

    test('does not admit an eleventh connected hunter', () {
      expect(
        ArenaRoomPolicy.canAcceptPlayer(
          connectedCount: 9,
          alreadyConnected: false,
        ),
        isTrue,
      );
      expect(
        ArenaRoomPolicy.canAcceptPlayer(
          connectedCount: 10,
          alreadyConnected: false,
        ),
        isFalse,
      );
    });

    test('reconnecting a disconnected hunter consumes a slot', () {
      expect(
        ArenaRoomPolicy.canAcceptPlayer(
          connectedCount: 10,
          alreadyConnected: false,
        ),
        isFalse,
      );
      expect(
        ArenaRoomPolicy.canAcceptPlayer(
          connectedCount: 10,
          alreadyConnected: true,
        ),
        isTrue,
      );
    });
  });
}
