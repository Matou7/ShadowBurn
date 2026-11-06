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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'rarity': rarity,
        'durationSeconds': durationSeconds,
      };

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        rarity: json['rarity'] ?? 'NORMALE',
        durationSeconds: json['durationSeconds'] ?? 0,
      );
}