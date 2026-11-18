// lib/services/audio_service.dart

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../core/log.dart';
import 'universal_audio_stub.dart' if (dart.library.html) 'universal_audio_web.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();
  static bool isPlaying = false;
  static const String _streamUrl =
      'https://streaming.nrjaudio.fm/ouf274tx4thg?origine=fluxradios&aw_0_1st.station=NRJ-Extravadance-Summer-2026';

  static Future<void> _play(String file) async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(
        AssetSource('audio/$file'),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      dlog("Erreur audio ($file) : $e");
    }
  }

  static Future<void> playLevelUp() => _play('level_up.mp3');
  static Future<void> playVictory() => _play('victory.mp3');
  static Future<void> playDefeat() => _play('defeat.mp3');
  static Future<void> playNationGoal() => _play('goal.mp3');
  static Future<void> playSystemNotification() => _play('notifications.mp3');

  // --- MÉTHODE DE SYNCHRONISATION DU FLUX NRJ (WEB & NATIF) ---
  static Future<bool> setNrjStreamState(bool shouldPlay) async {
    try {
      if (kIsWeb) {
        isPlaying = UniversalAudioWeb.setPlaying(shouldPlay);
      } else {
        if (shouldPlay) {
          await _player.setReleaseMode(ReleaseMode.loop);
          await _player.play(UrlSource(_streamUrl), mode: PlayerMode.mediaPlayer);
          isPlaying = true;
        } else {
          await _player.stop();
          isPlaying = false;
        }
      }
      dlog("[AUDIO SERVICE] État du flux radio imposé - Lecture : $isPlaying");
      return isPlaying;
    } catch (e) {
      dlog("[AUDIO SERVICE] Erreur setNrjStreamState : $e");
      return isPlaying;
    }
  }

  static Future<bool> toggleNrjStream() async {
    return setNrjStreamState(!isPlaying);
  }

  static Future<void> stopNrjStream() async {
    await setNrjStreamState(false);
  }
}