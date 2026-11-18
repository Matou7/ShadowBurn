// lib/services/universal_audio_web.dart
import 'dart:js' as js;
import '../core/log.dart';

class UniversalAudioWeb {
  static bool setPlaying(bool play) {
    try {
      var result = js.context.callMethod('setWebRadioState', [play]);
      dlog("[WEB AUDIO] État radio forcé à $play -> $result");
      return result == true;
    } catch (e) {
      dlog("[WEB AUDIO] Erreur interop JS setWebRadioState : $e");
      return false;
    }
  }

  static bool toggle() {
    try {
      var result = js.context.callMethod('toggleWebRadio');
      dlog("[WEB AUDIO] Bascule radio exécutée : $result");
      return result == true;
    } catch (e) {
      dlog("[WEB AUDIO] Erreur bascule interop JS : $e");
      return false;
    }
  }

  static void stop() {
    try {
      js.context.callMethod('stopWebRadio');
      dlog("[WEB AUDIO] Stoppé.");
    } catch (e) {
      dlog("[WEB AUDIO] Erreur d'arrêt : $e");
    }
  }
}