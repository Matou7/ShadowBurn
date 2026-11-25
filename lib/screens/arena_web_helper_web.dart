// lib/screens/arena_web_helper_web.dart

import 'dart:js_interop';
import 'package:web/web.dart' as web;

class ArenaWebHelper {
  static void registerBeforeUnload(void Function() onUnload) {
    final JSFunction listener = ((web.Event _) {
      onUnload();
    }).toJS;
    web.window.addEventListener('beforeunload', listener);
  }
}