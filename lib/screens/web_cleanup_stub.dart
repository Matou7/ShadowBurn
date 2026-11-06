library web_cleanup;

void registerTabCloseCleanup(bool Function() isJoined, String Function() getRoomId, String Function() getSessionId) {
  // No-op for mobile targets
}