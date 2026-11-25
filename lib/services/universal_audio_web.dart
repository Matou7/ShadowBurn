// lib/services/universal_audio_web.dart

import 'dart:js_interop';
import '../core/log.dart';

@JS('setWebRadioState')
external JSAny? _jsSetWebRadioState(JSBoolean play);

@JS('toggleWebRadio')
external JSAny? _jsToggleWebRadio();

@JS('stopWebRadio')
external JSAny? _jsStopWebRadio();

class UniversalAudioWeb {
  static bool setPlaying(bool play) {
    try {
      final result = _jsSetWebRadioState(play.toJS);
      dlog("[WEB AUDIO] État radio forcé à $play -> $result");
      return result?.dartify() == true;
    } catch (e) {
      dlog("[WEB AUDIO] Erreur interop JS setWebRadioState : $e");
      return false;
    }
  }

  static bool toggle() {
    try {
      final result = _jsToggleWebRadio();
      dlog("[WEB AUDIO] Bascule radio exécutée : $result");
      return result?.dartify() == true;
    } catch (e) {
      dlog("[WEB AUDIO] Erreur bascule interop JS : $e");
      return false;
    }
  }

  static void stop() {
    try {
      _jsStopWebRadio();
      dlog("[WEB AUDIO] Stoppé.");
    } catch (e) {
      dlog("[WEB AUDIO] Erreur d'arrêt : $e");
    }
  }
}