// lib/core/balance.dart
/// ============================================================
///   TABLE D'ÉQUILIBRAGE UNIQUE — une ligne par rang.
/// ============================================================
class RankConfig {
  final String id;
  final int index;
  final double goalKm;             // objectif km quotidien
  final int goalExo;               // objectif quotidien (pompes / abdos / squats)
  final int maxHp;
  final int attribute;             // force = endurance
  final double xpFloor;            // XP minimum du rang
  final double xpNext;             // XP pour monter au rang suivant
  final int cycleReward;           // XP d'un cycle quotidien validé
  final int urgentReward;          // XP d'une quête urgente réussie
  final int urgentPenalty;         // perte d'XP si fuite / temps écoulé
  final int missedDayPenalty;      // perte d'XP par jour raté
  final int dungeonReward;         // XP d'un donjon réussi
  final int dungeonPenalty;        // perte d'XP si fuite / temps écoulé
  final int dungeonSeconds;        // DURÉE TEST : en secondes (10s pour test)
  final double urgentMultiplier;   // difficulté des quêtes urgentes
  final int colorValue;            // couleur du rang (ARGB)

  const RankConfig({
    required this.id,
    required this.index,
    required this.goalKm,
    required this.goalExo,
    required this.maxHp,
    required this.attribute,
    required this.xpFloor,
    required this.xpNext,
    required this.cycleReward,
    required this.urgentReward,
    required this.urgentPenalty,
    required this.missedDayPenalty,
    required this.dungeonReward,
    required this.dungeonPenalty,
    required this.dungeonSeconds,
    required this.urgentMultiplier,
    required this.colorValue,
  });

  int get dungeonReps => goalExo + 10;
}

class Balance {
  static const List<String> order = ["E", "D", "C", "B", "A", "S", "NATION", "MONARQUE"];

  static const Map<String, RankConfig> ranks = {
    "E": RankConfig(
      id: "E", index: 0, goalKm: 1.0, goalExo: 10, maxHp: 100, attribute: 10,
      xpFloor: 0, xpNext: 1000000,
      cycleReward: 600, urgentReward: 100, urgentPenalty: 500, missedDayPenalty: 2000,
      dungeonReward: 900, dungeonPenalty: 1500, dungeonSeconds: 10,
      urgentMultiplier: 1.0, colorValue: 0xFFB0BEC5,
    ),
    "D": RankConfig(
      id: "D", index: 1, goalKm: 1.5, goalExo: 20, maxHp: 200, attribute: 40,
      xpFloor: 1000001, xpNext: 5000000,
      cycleReward: 1200, urgentReward: 300, urgentPenalty: 1000, missedDayPenalty: 5000,
      dungeonReward: 2500, dungeonPenalty: 4000, dungeonSeconds: 10,
      urgentMultiplier: 1.5, colorValue: 0xFF4CAF50,
    ),
    "C": RankConfig(
      id: "C", index: 2, goalKm: 2.0, goalExo: 40, maxHp: 500, attribute: 80,
      xpFloor: 5000001, xpNext: 20000000,
      cycleReward: 3000, urgentReward: 800, urgentPenalty: 5000, missedDayPenalty: 15000,
      dungeonReward: 10000, dungeonPenalty: 15000, dungeonSeconds: 10,
      urgentMultiplier: 2.0, colorValue: 0xFF2196F3,
    ),
    "B": RankConfig(
      id: "B", index: 3, goalKm: 3.0, goalExo: 60, maxHp: 1000, attribute: 150,
      xpFloor: 20000001, xpNext: 50000000,
      cycleReward: 8000, urgentReward: 2000, urgentPenalty: 20000, missedDayPenalty: 40000,
      dungeonReward: 50000, dungeonPenalty: 75000, dungeonSeconds: 10,
      urgentMultiplier: 3.0, colorValue: 0xFF9C27B0,
    ),
    "A": RankConfig(
      id: "A", index: 4, goalKm: 5.0, goalExo: 80, maxHp: 2000, attribute: 250,
      xpFloor: 50000001, xpNext: 200000000,
      cycleReward: 25000, urgentReward: 6000, urgentPenalty: 50000, missedDayPenalty: 100000,
      dungeonReward: 200000, dungeonPenalty: 300000, dungeonSeconds: 10,
      urgentMultiplier: 4.0, colorValue: 0xFFF44336,
    ),
    "S": RankConfig(
      id: "S", index: 5, goalKm: 10.0, goalExo: 100, maxHp: 5000, attribute: 500,
      xpFloor: 200000001, xpNext: 1000000000,
      cycleReward: 2500500, urgentReward: 50000, urgentPenalty: 200000, missedDayPenalty: 500000,
      dungeonReward: 2500000, dungeonPenalty: 4000000, dungeonSeconds: 10,
      urgentMultiplier: 5.0, colorValue: 0xFFFFD700,
    ),
    "NATION": RankConfig(
      id: "NATION", index: 6, goalKm: 15.0, goalExo: 150, maxHp: 15000, attribute: 1000,
      xpFloor: 1000000001, xpNext: 1000000000000,
      cycleReward: 5000000, urgentReward: 1000000, urgentPenalty: 5000000, missedDayPenalty: 0,
      dungeonReward: 50000000, dungeonPenalty: 75000000, dungeonSeconds: 10,
      urgentMultiplier: 10.0, colorValue: 0xFF00E5FF,
    ),
    "MONARQUE": RankConfig(
      id: "MONARQUE", index: 7, goalKm: 20.0, goalExo: 200, maxHp: 50000, attribute: 2500,
      xpFloor: 1000000000001, xpNext: 1000000000000,
      cycleReward: 25000000, urgentReward: 5000000, urgentPenalty: 0, missedDayPenalty: 0,
      dungeonReward: 250000000, dungeonPenalty: 0, dungeonSeconds: 10,
      urgentMultiplier: 20.0, colorValue: 0xFF9400D3,
    ),
  };

  static RankConfig of(String rank) => ranks[rank] ?? ranks["E"]!;

  static String? next(String rank) {
    final i = order.indexOf(rank);
    if (i < 0 || i >= order.length - 1) return null;
    return order[i + 1];
  }

  static const double classChangeXp = 1000000000;
  static const double classChangeNationXp = 1000000000;
  static const double classChangeMonarqueXp = 1000000000000;
  static const double classChangeFailPenalty = 100000000;
}