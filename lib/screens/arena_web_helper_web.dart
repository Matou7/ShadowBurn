import 'dart:html' as html;

class ArenaWebHelper {
  static void registerBeforeUnload(Function() onUnload) {
    html.window.onBeforeUnload.listen((event) {
      onUnload();
    });
  }
}