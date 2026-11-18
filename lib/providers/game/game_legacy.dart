// lib/providers/game/game_legacy.dart
part of '../game_provider.dart';

/// COMPATIBILITÉ : membres exigés par les écrans titles_screen.dart, arise_overlay.dart
/// et level_up_overlay.dart.
mixin _LegacyUiCompat on _GameBase {
  bool areTitlesActive = true;
  String titlesCooldown = "00:00:00";
  bool isBossKneeling = false;
  bool showAriseEffect = false;
  int shadowExtractionAttempts = 3;

  void attemptArise([dynamic arg]) {
    showAriseEffect = true;
    notifyListeners();
  }

  void cancelExtraction() {
    isBossKneeling = false;
    showAriseEffect = false;
    notifyListeners();
  }

  void closeLevelUpOverlay() {
    notifyListeners();
  }
}