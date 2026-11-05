import 'package:audioplayers/audioplayers.dart';
import '../core/log.dart';

/// Les noms de fichiers correspondent EXACTEMENT à ceux du dossier assets/audio/.
class AudioService {
  static final AudioPlayer _player = AudioPlayer();

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
}