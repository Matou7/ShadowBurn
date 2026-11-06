// lib/models/dungeon.dart
class Dungeon {
  final String id;
  final String rank;
  final List<dynamic> tasks;
  final List<double> progress;
  DateTime expiresAt;
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

  double get maxBossHp {
    double total = 0;
    for (var task in tasks) {
      if (task is Map && task.containsKey('amount')) {
        total += (task['amount'] as num).toDouble();
      }
    }
    return total > 0 ? total : 1.0;
  }

  double get currentBossHp {
    double totalProgress = 0;
    for (var p in progress) {
      totalProgress += p;
    }
    return (maxBossHp - totalProgress).clamp(0.0, maxBossHp);
  }

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
        id: json['id'] ?? '',
        rank: json['rank'] ?? 'E',
        tasks: List<dynamic>.from(json['tasks'] ?? const []),
        progress: List<double>.from((json['progress'] ?? const []).map((x) => (x as num).toDouble())),
        expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : DateTime.now(),
        xpReward: json['xpReward'] ?? 0,
        penaltyXp: json['penaltyXp'] ?? 0,
        isRandomThreat: json['isRandomThreat'] ?? false,
      );
}