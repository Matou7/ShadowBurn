part of '../game_provider.dart';

/// COMPATIBILITÉ : membres exigés par les anciens écrans titles_screen.dart et arise_overlay.dart,
/// qui ne sont plus utilisés. Quand tu supprimes ces deux fichiers, supprime aussi CE fichier
/// et retire "_LegacyUiCompat" dans game_provider.dart.
mixin _LegacyUiCompat on _GameBase {
  bool areTitlesActive = true;
  String titlesCooldown = "00:00:00";
  bool isBossKneeling = false;
  bool showAriseEffect = false;
  int shadowExtractionAttempts = 3;

  void attemptArise([dynamic arg]) {
    showAriseEffect = true;
    _notify();
  }

  void closeLevelUpOverlay() {
    closeResultScreen();
  }

  void cancelExtraction() {
    isBossKneeling = false;
    showAriseEffect = false;
    _notify();
  }
}
