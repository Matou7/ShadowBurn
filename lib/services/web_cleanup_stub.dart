// lib/services/web_cleanup_stub.dart
library web_cleanup;

void registerTabCloseCleanup(
  bool Function() isJoined, 
  String Function() getRoomId, 
  String Function() getSessionId,
) {
  // Deterministic no-op for non-web targets (Android, iOS, Desktop)
}