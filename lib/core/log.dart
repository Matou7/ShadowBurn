// lib/core/log.dart
import 'package:flutter/foundation.dart';

/// Remplace print() : n'écrit rien dans la version finale (release).
void dlog(String message) {
  if (kDebugMode) debugPrint(message);
}