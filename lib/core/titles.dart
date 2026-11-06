// lib/core/titles.dart
/// ============================================================
///   CATALOGUE DES TITRES — pour en ajouter un, ajoute une ligne.
///   Un titre se débloque automatiquement quand sa condition est vraie.
/// ============================================================
class TitleStats {
  final int rankIndex; // E=0, D=1, C=2, B=3, A=4, S=5, NATION=6, MONARQUE=7
  final int streak;
  final int pompes;
  final int abdos;
  final int squats;
  final double km;
  final int dungeons;
  final int surpass;

  const TitleStats({
    required this.rankIndex,
    required this.streak,
    required this.pompes,
    required this.abdos,
    required this.squats,
    required this.km,
    required this.dungeons,
    required this.surpass,
  });
}

class TitleDef {
  final String name;
  final String requirement; // texte affiché pour les titres verrouillés
  final bool Function(TitleStats s) isUnlocked;
  const TitleDef(this.name, this.requirement, this.isUnlocked);
}

class Titles {
  static const String defaultTitle = "Nouveau Chasseur";

  static final List<TitleDef> catalog = [
    TitleDef(defaultTitle, "Titre de départ", (s) => true),

    // --- Rangs (Nouveaux intitulés validés) ---
    TitleDef("Lame Naissante", "Atteindre le rang D", (s) => s.rankIndex >= 1),
    TitleDef("Traqueur d'Élite", "Atteindre le rang C", (s) => s.rankIndex >= 2),
    TitleDef("Marteau des Donjons", "Atteindre le rang B", (s) => s.rankIndex >= 3),
    TitleDef("Fléau des Portails", "Atteindre le rang A", (s) => s.rankIndex >= 4),
    TitleDef("Seigneur de Guerre", "Atteindre le rang S", (s) => s.rankIndex >= 5),
    TitleDef("Autorité Nationale", "Atteindre le rang NATION", (s) => s.rankIndex >= 6),
    TitleDef("Monarque des Ombres", "Atteindre le rang MONARQUE", (s) => s.rankIndex >= 7),

    // --- Discipline (série de jours) ---
    TitleDef("Régulier", "Série de 7 jours", (s) => s.streak >= 7),
    TitleDef("Inflexible", "Série de 30 jours", (s) => s.streak >= 30),
    TitleDef("Volonté d'Acier", "Série de 100 jours", (s) => s.streak >= 100),

    // --- Force ---
    TitleDef("Poings d'Acier", "1 000 pompes au total", (s) => s.pompes >= 1000),
    TitleDef("Briseur de Murs", "10 000 pompes au total", (s) => s.pompes >= 10000),
    TitleDef("Ventre de Fer", "1 000 abdos au total", (s) => s.abdos >= 1000),
    TitleDef("Gainage Absolu", "5 000 abdos au total", (s) => s.abdos >= 5000),
    TitleDef("Jambes de Titan", "5 000 squats au total", (s) => s.squats >= 5000),
    TitleDef("Pilier Inébranlable", "20 000 squats au total", (s) => s.squats >= 20000),

    // --- Endurance ---
    TitleDef("Coureur des Ombres", "100 km au total", (s) => s.km >= 100),
    TitleDef("Marathonien Spectral", "500 km au total", (s) => s.km >= 500),

    // --- Donjons & surpassement ---
    TitleDef("Pilleur de Donjons", "10 donjons réussis", (s) => s.dungeons >= 10),
    TitleDef("Briseur de Portails", "50 donjons réussis", (s) => s.dungeons >= 50),
    TitleDef("Au-delà des Limites", "10 surpassements", (s) => s.surpass >= 10),

    // --- Hauts Faits Spéciaux ---
    TitleDef("Incinérateur", "5 000 squats cumulés", (s) => s.squats >= 5000),
    TitleDef("Spectre d'Acier", "10 donjons réussis", (s) => s.dungeons >= 10),
  ];
}