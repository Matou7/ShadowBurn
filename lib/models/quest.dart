// lib/models/quest.dart

class Quest {
  final String id;
  final String title;
  final String description;
  final String rarity; 
  final int durationSeconds;

  Quest({
    required this.id,
    required this.title,
    required this.description,
    required this.rarity,
    required this.durationSeconds,
  });
}