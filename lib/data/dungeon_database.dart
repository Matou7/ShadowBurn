// lib/data/dungeon_database.dart
import '../core/balance.dart';

/// Ancien fichier de paliers : tout est maintenant dans core/balance.dart.
/// Il ne reste ici que ce dont d'autres écrans pourraient encore avoir besoin.
class DungeonDatabase {
  static const List<String> ranks = Balance.order;

  static Map<String, dynamic> generateDungeonData(String rank) {
    final cfg = Balance.of(rank);
    final int reps = cfg.dungeonReps;
    return {
      'duration': Duration(seconds: cfg.dungeonSeconds),
      'tasks': [
        {"type": "POMPES", "amount": reps.toDouble(), "title": "Pompes"},
        {"type": "SQUATS", "amount": reps.toDouble(), "title": "Squats"},
        {"type": "ABDOS", "amount": reps.toDouble(), "title": "Abdos"},
      ],
    };
  }
}