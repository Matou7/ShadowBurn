class Dungeon {
  final String id;
  final String rank;
  final List<dynamic> tasks;
  final List<double> progress;
  DateTime expiresAt; // Non-final pour mise à jour possible si extension de temps
  final int xpReward;
  final int penaltyXp;
  final bool isRandomThreat;

  Dungeon({
    required this.id,
    required this.rank,
    required this.tasks,
    required this.progress,
    required this.expiresAt,
    required this.xpReward,
    required this.penaltyXp,
    required this.isRandomThreat,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'rank': rank,
    'tasks': tasks,
    'progress': progress,
    'expiresAt': expiresAt.toIso8601String(),
    'xpReward': xpReward,
    'penaltyXp': penaltyXp,
    'isRandomThreat': isRandomThreat,
  };

  factory Dungeon.fromJson(Map<String, dynamic> json) => Dungeon(
    id: json['id'],
    rank: json['rank'],
    tasks: json['tasks'],
    progress: List<double>.from(json['progress'].map((x) => x.toDouble())), // Conversion explicite double
    expiresAt: DateTime.parse(json['expiresAt']),
    xpReward: json['xpReward'],
    penaltyXp: json['penaltyXp'],
    isRandomThreat: json['isRandomThreat'] ?? false,
  );
}