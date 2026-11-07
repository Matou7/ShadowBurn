// lib/services/audio_service.dart

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../core/log.dart';
import 'universal_audio_stub.dart' if (dart.library.html) 'universal_audio_web.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();
  static bool isPlaying = false;

  static Future<void> _play(String file) async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(
        AssetSource('audio/$file'),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      dlog("Erreur audio ($file) :$e");
    }
  }

  static Future<void> playLevelUp() => _play('level_up.mp3');
  static Future<void> playVictory() => _play('victory.mp3');
  static Future<void> playDefeat() => _play('defeat.mp3');
  static Future<void> playNationGoal() => _play('goal.mp3');
  static Future<void> playSystemNotification() => _play('notifications.mp3');

  // --- BASCULE LECTURE / PAUSE DU FLUX SÉCURISÉ ---
  static Future<bool> toggleNrjStream() async {
    try {
      const String streamUrl = 'https://streaming.nrjaudio.fm/ouf274tx4thg?origine=fluxradios&aw_0_1st.station=NRJ-Extravadance-Summer-2026';
      if (kIsWeb) {
        isPlaying = UniversalAudioWeb.toggle();
      } else {
        if (isPlaying) {
          await _player.pause();
          isPlaying = false;
        } else {
          await _player.setReleaseMode(ReleaseMode.loop);
          await _player.play(UrlSource(streamUrl), mode: PlayerMode.mediaPlayer);
          isPlaying = true;
        }
      }
      dlog("[AUDIO SERVICE] État du flux radio - Lecture : $isPlaying");
      return isPlaying;
    } catch (e) {
      dlog("[AUDIO SERVICE] Erreur bascule flux radio : $e");
      return isPlaying;
    }
  }

  static Future<void> stopNrjStream() async {
    try {
      if (kIsWeb) {
        UniversalAudioWeb.stop();
      } else {
        await _player.stop();
      }
      isPlaying = false;
      dlog("[AUDIO SERVICE] Flux radio stoppé.");
    } catch (e) {
      dlog("[AUDIO SERVICE] Erreur arrêt flux radio : $e");
    }
  }
}