// lib/services/web_cleanup.dart
library web_cleanup;

import 'web_cleanup_stub.dart' 
    if (dart.library.html) 'web_cleanup_web.dart' as impl;

void registerTabCloseCleanup(
  bool Function() isJoined, 
  String Function() getRoomId, 
  String Function() getSessionId,
) {
  impl.registerTabCloseCleanup(isJoined, getRoomId, getSessionId);
}