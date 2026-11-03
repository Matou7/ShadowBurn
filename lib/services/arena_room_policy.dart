/// Shared, testable limits for the client-authoritative Arena.
class ArenaRoomPolicy {
  const ArenaRoomPolicy._();

  static const int maxGlobalRooms = 100;
  static const int maxPlayersPerRoom = 10;

  /// Returns the valid room number for room_1..room_100, otherwise null.
  static int? parseRoomNumber(String? roomId) {
    final normalized = roomId?.trim() ?? '';
    if (!normalized.startsWith('room_')) return null;
    final number = int.tryParse(normalized.substring(5));
    if (number == null ||
        number < 1 ||
        number > maxGlobalRooms ||
        normalized != 'room_$number') {
      return null;
    }
    return number;
  }

  /// A disconnected player consumes a slot when reconnecting.
  static bool canAcceptPlayer({
    required int connectedCount,
    required bool alreadyConnected,
  }) {
    return alreadyConnected || connectedCount < maxPlayersPerRoom;
  }
}
