import 'dart:math';

class DungeonDatabase {
  static const List<String> ranks = ["E", "D", "C", "B", "A", "S", "NATION"];

  // MAJ : Paliers alignés sur l'objectif 1 Milliard (1 000 000 000)
  // Ce chiffre est le PLAFOND du rang précédent (ce qu'il faut battre pour monter)
  static const Map<String, int> xpRequirements = {
    "E": 0,
    "D": 5000,
    "C": 25000,
    "B": 150000,
    "A": 1000000,       // 1 Million
    "S": 100000000,     // 100 Millions (Seuil pour entrer en S)
    "NATION": 1000000000 // 1 Milliard (Seuil pour entrer en Nation)
  };

  // CONFIGURATION DES TÂCHES ET OBJECTIFS
  static const Map<String, dynamic> rankData = {
    "E": {
      "durationMinutes": 10,
      "tasks": [
        {"type": "POMPES", "amount": 10.0, "title": "Force: 10 Pompes"},
        {"type": "SQUATS", "amount": 10.0, "title": "Jambes: 10 Squats"}
      ],
      "OBJECTIF": {"KM": 1.0, "PUSHUPS": 10, "SITUPS": 10, "SQUATS": 10}
    },
    "D": {
      "durationMinutes": 20,
      "tasks": [
        {"type": "POMPES", "amount": 20.0, "title": "Force: 20 Pompes"},
        {"type": "ABDOS", "amount": 20.0, "title": "Gainage: 20 Abdos"},
        {"type": "KM", "amount": 0.5, "title": "Sprint: 500m"}
      ],
      "OBJECTIF": {"KM": 2.0, "PUSHUPS": 20, "SITUPS": 20, "SQUATS": 20}
    },
    "C": {
      "durationMinutes": 30,
      "tasks": [
        {"type": "POMPES", "amount": 40.0, "title": "Force: 40 Pompes"},
        {"type": "SQUATS", "amount": 40.0, "title": "Jambes: 40 Squats"},
        {"type": "KM", "amount": 1.5, "title": "Course: 1.5 km"}
      ],
      "OBJECTIF": {"KM": 3.0, "PUSHUPS": 30, "SITUPS": 30, "SQUATS": 30}
    },
    "B": {
      "durationMinutes": 45,
      "tasks": [
        {"type": "POMPES", "amount": 60.0, "title": "Force: 60 Pompes"},
        {"type": "ABDOS", "amount": 100.0, "title": "Abdos: 100 Reps"},
        {"type": "KM", "amount": 3.0, "title": "Endurance: 3 km"}
      ],
      "OBJECTIF": {"KM": 5.0, "PUSHUPS": 50, "SITUPS": 50, "SQUATS": 50}
    },
    "A": {
      "durationMinutes": 60,
      "tasks": [
        {"type": "POMPES", "amount": 100.0, "title": "Armée: 100 Pompes"},
        {"type": "SQUATS", "amount": 100.0, "title": "Jambes: 100 Squats"},
        {"type": "KM", "amount": 5.0, "title": "Marathon: 5 km"}
      ],
      "OBJECTIF": {"KM": 8.0, "PUSHUPS": 80, "SITUPS": 80, "SQUATS": 80}
    },
    "S": {
      "durationMinutes": 120,
      "tasks": [
        {"type": "POMPES", "amount": 200.0, "title": "Titan: 200 Pompes"},
        {"type": "ABDOS", "amount": 200.0, "title": "Acier: 200 Abdos"},
        {"type": "KM", "amount": 10.0, "title": "Légende: 10 km"}
      ],
      "OBJECTIF": {"KM": 10.0, "PUSHUPS": 100, "SITUPS": 100, "SQUATS": 100}
    },
    "NATION": {
      "durationMinutes": 240,
      "tasks": [
        {"type": "POMPES", "amount": 500.0, "title": "Divin: 500 Pompes"},
        {"type": "KM", "amount": 20.0, "title": "Monde: 20 km"}
      ],
      "OBJECTIF": {
        "KM": 20.0, 
        "PUSHUPS": 200, 
        "SITUPS": 200, 
        "SQUATS": 200
      }
    },
  };

  static Map<String, dynamic> generateDungeonData(String rank) {
    var data = rankData[rank] ?? rankData["E"];
    List<Map<String, dynamic>> safeTasks = [];
    for (var t in data['tasks']) {
      safeTasks.add(Map<String, dynamic>.from(t));
    }
    
    return {
      'duration': Duration(minutes: data['durationMinutes']),
      'tasks': safeTasks
    };
  }
}