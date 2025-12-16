// lib/models/seance_config.dart
// Configuration des séances de la journée

class SeanceConfig {
  // Définition des 9 séances de la journée (8h - 17h)
  static const List<Map<String, dynamic>> seances = [
    {
      "id": "S1",
      "nom": "Séance 1",
      "debut": "08:00",
      "fin": "09:00",
      "retard_limite": "08:10", // 10 minutes de grâce
    },
    {
      "id": "S2",
      "nom": "Séance 2",
      "debut": "09:00",
      "fin": "10:00",
      "retard_limite": "09:10",
    },
    {
      "id": "S3",
      "nom": "Séance 3",
      "debut": "10:00",
      "fin": "11:00",
      "retard_limite": "10:10",
    },
    {
      "id": "S4",
      "nom": "Séance 4",
      "debut": "11:00",
      "fin": "12:00",
      "retard_limite": "11:10",
    },
    {
      "id": "S5",
      "nom": "Séance 5 (Après-midi)",
      "debut": "13:00",
      "fin": "14:00",
      "retard_limite": "13:10",
    },
    {
      "id": "S6",
      "nom": "Séance 6",
      "debut": "14:00",
      "fin": "15:00",
      "retard_limite": "14:10",
    },
    {
      "id": "S7",
      "nom": "Séance 7",
      "debut": "15:00",
      "fin": "16:00",
      "retard_limite": "15:10",
    },
    {
      "id": "S8",
      "nom": "Séance 8",
      "debut": "16:00",
      "fin": "17:00",
      "retard_limite": "16:10",
    },
  ];

  /// Retourne la séance actuelle basée sur l'heure
  static Map<String, dynamic>? getSeanceActuelle() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (var seance in seances) {
      final debutParts = (seance["debut"] as String).split(":");
      final finParts = (seance["fin"] as String).split(":");
      
      final debutMinutes = int.parse(debutParts[0]) * 60 + int.parse(debutParts[1]);
      final finMinutes = int.parse(finParts[0]) * 60 + int.parse(finParts[1]);

      if (currentMinutes >= debutMinutes && currentMinutes < finMinutes) {
        return seance;
      }
    }
    return null; // En dehors des heures de cours
  }

  /// Vérifie si l'élève peut entrer (dans les 10 minutes de grâce)
  static bool peutEntrer(String seanceId, {DateTime? heureCustom}) {
    final seance = seances.firstWhere((s) => s["id"] == seanceId, orElse: () => {});
    if (seance.isEmpty) return false;

    final now = heureCustom ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final debutParts = (seance["debut"] as String).split(":");
    final retardParts = (seance["retard_limite"] as String).split(":");
    
    final debutMinutes = int.parse(debutParts[0]) * 60 + int.parse(debutParts[1]);
    final retardMinutes = int.parse(retardParts[0]) * 60 + int.parse(retardParts[1]);

    // L'élève peut entrer si on est entre le début et la limite de retard
    return currentMinutes >= debutMinutes && currentMinutes <= retardMinutes;
  }

  /// Vérifie si l'élève est en retard (après 8h mais avant 8h10 par exemple)
  static bool estEnRetard(String seanceId, {DateTime? heureCustom}) {
    final seance = seances.firstWhere((s) => s["id"] == seanceId, orElse: () => {});
    if (seance.isEmpty) return false;

    final now = heureCustom ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final debutParts = (seance["debut"] as String).split(":");
    // On considère en retard après les 5 premières minutes
    final debutMinutes = int.parse(debutParts[0]) * 60 + int.parse(debutParts[1]);

    return currentMinutes > debutMinutes + 5;
  }

  /// Retourne la séance suivante
  static Map<String, dynamic>? getSeanceSuivante(String seanceId) {
    final index = seances.indexWhere((s) => s["id"] == seanceId);
    if (index >= 0 && index < seances.length - 1) {
      return seances[index + 1];
    }
    return null;
  }

  /// Retourne toutes les séances jusqu'à une heure donnée
  static List<Map<String, dynamic>> getSeancesJusquA(String heureMax) {
    final maxParts = heureMax.split(":");
    final maxMinutes = int.parse(maxParts[0]) * 60 + int.parse(maxParts[1]);

    return seances.where((seance) {
      final finParts = (seance["fin"] as String).split(":");
      final finMinutes = int.parse(finParts[0]) * 60 + int.parse(finParts[1]);
      return finMinutes <= maxMinutes;
    }).toList();
  }

  /// Convertit une heure string en minutes depuis minuit
  static int heureEnMinutes(String heure) {
    final parts = heure.split(":");
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Convertit des minutes en heure string
  static String minutesEnHeure(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }
}


