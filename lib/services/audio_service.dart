import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playLevelUp() async {
    await _player.play(AssetSource('audio/levelup.mp3'));
  }

  static Future<void> playVictory() async {
    await _player.play(AssetSource('audio/victory.mp3'));
  }

  static Future<void> playDefeat() async {
    await _player.play(AssetSource('audio/defeat.mp3'));
  }

  static Future<void> playNationGoal() async {
    await _player.play(AssetSource('audio/nation.mp3'));
  }

  // --- SON DES POPUPS HOLOGRAPHIQUES ---
  static Future<void> playSystemNotification() async {
    try {
      await _player.stop(); 
      // Assure-toi que le fichier est bien dans assets/audio/
      await _player.play(AssetSource('audio/notifications.mp3'));
    } catch (e) {
      print("Erreur Audio Notification: $e");
    }
  }
}