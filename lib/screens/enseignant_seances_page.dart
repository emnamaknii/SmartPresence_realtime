// lib/screens/enseignant_seances_page.dart
// Page enseignant avec gestion des séances

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/seance_config.dart';
import 'pointage_seance_page.dart';

class EnseignantSeancesPage extends StatefulWidget {
  const EnseignantSeancesPage({super.key});

  @override
  State<EnseignantSeancesPage> createState() => _EnseignantSeancesPageState();
}

class _EnseignantSeancesPageState extends State<EnseignantSeancesPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final DatabaseReference db = FirebaseDatabase.instance.ref();
  final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  List<Map<String, dynamic>> classes = [];
  bool isLoading = true;
  String? enseignantId;
  String? enseignantNom;
  Map<String, dynamic>? seanceActuelle;

  final List<StreamSubscription> _subscriptions = [];
  Timer? _timerSeance;

  // Configuration ESP32
  static const String esp32Ip = "172.20.10.6";

  @override
  void initState() {
    super.initState();
    seanceActuelle = SeanceConfig.getSeanceActuelle();
    
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, "/login");
      });
    } else {
      chargerTout();
      // Mettre à jour la séance actuelle chaque minute
      _timerSeance = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) {
          setState(() {
            seanceActuelle = SeanceConfig.getSeanceActuelle();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _timerSeance?.cancel();
    super.dispose();
  }

  Future<void> chargerTout() async {
    // 1. Trouver l'ID ENSxxx via le uid
    final snap = await db.child("enseignants").orderByChild("uid").equalTo(user!.uid).once();
    if (!snap.snapshot.exists) {
      FirebaseAuth.instance.signOut();
      return;
    }
    
    final ensData = (snap.snapshot.value as Map).values.first as Map;
    enseignantId = (snap.snapshot.value as Map).keys.first as String;
    enseignantNom = "${ensData["prenom"] ?? ""} ${ensData["nom"] ?? ""}".trim();

    // 2. Charger les classes initialement
    await _chargerClasses();
    
    // 3. Écouter les changements des classes de l'enseignant
    final classesSub = db.child("enseignants/$enseignantId/classes").onValue.listen((event) async {
      if (!mounted) return;
      await _chargerClasses();
    });
    _subscriptions.add(classesSub);
    
    // 4. Écouter les changements des étudiants (ajout/suppression)
    final etudiantsSub = db.child("etudiants").onValue.listen((event) {
      if (!mounted) return;
      _chargerClasses(); // Recharger quand un étudiant est modifié
    });
    _subscriptions.add(etudiantsSub);
  }
  
  Future<void> _chargerClasses() async {
    try {
      final enseignantClassesSnap = await db.child("enseignants/$enseignantId/classes").once();
      
      if (!enseignantClassesSnap.snapshot.exists || enseignantClassesSnap.snapshot.value == null) {
        if (mounted) {
          setState(() {
            classes = [];
            isLoading = false;
          });
        }
        return;
      }

      final Map classesMap = enseignantClassesSnap.snapshot.value as Map;
      List<Map<String, dynamic>> temp = [];

      for (String classeId in classesMap.keys) {
        final classeSnap = await db.child("classes/$classeId").once();
        if (!classeSnap.snapshot.exists) continue;
        final classeData = classeSnap.snapshot.value as Map;
        final nomClasse = classeData["nom"] ?? "Classe";

        // Récupérer les étudiants
        final Map etuMap = classeData["etudiants"] ?? {};
        List<Map<String, dynamic>> etudiants = [];

        for (String etuId in etuMap.keys) {
          final etuSnap = await db.child("etudiants/$etuId").once();
          if (!etuSnap.snapshot.exists) continue;
          final etuData = etuSnap.snapshot.value as Map;

          etudiants.add({
            "id": etuId,
            "nom": etuData["nom"] ?? "",
            "prenom": etuData["prenom"] ?? "",
            "empreinte_id": etuData["empreinte_id"] ?? 0,
            "email_parent": etuData["email_parent"] ?? "",
          });
        }

        etudiants.sort((a, b) => (a["nom"] ?? "").toString().compareTo((b["nom"] ?? "").toString()));

        temp.add({
          "id": classeId,
          "nom": nomClasse,
          "etudiants": etudiants,
        });
      }

      temp.sort((a, b) => (a["nom"] ?? "").toString().compareTo((b["nom"] ?? "").toString()));

      if (mounted) {
        setState(() {
          classes = temp;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur chargement classes: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _deconnexion() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment vous déconnecter ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB721D)),
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(context, "/login", (r) => false);
            },
            child: const Text("Oui", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _activerModePointage() async {
    try {
      await http.get(Uri.parse("http://$esp32Ip/mode?m=detection"));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Mode pointage activé !"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur ESP32 : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Mes Classes"),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.fingerprint, size: 28),
            onPressed: _activerModePointage,
            tooltip: "Activer le pointage",
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _deconnexion,
            tooltip: "Déconnexion",
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // En-tête avec info séance actuelle
                _buildSeanceHeader(),
                
                // Liste des classes
                Expanded(
                  child: classes.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: classes.length,
                          itemBuilder: (_, i) => _buildClasseCard(classes[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSeanceHeader() {
    final now = DateTime.now();
    final heureActuelle = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFFB721D),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                enseignantNom ?? "Enseignant",
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE d MMMM', 'fr_FR').format(now),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    heureActuelle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: seanceActuelle != null ? Colors.white : Colors.red[400],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      seanceActuelle != null ? seanceActuelle!["id"] : "PAUSE",
                      style: TextStyle(
                        color: seanceActuelle != null ? const Color(0xFFFB721D) : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    if (seanceActuelle != null)
                      Text(
                        "${seanceActuelle!["debut"]} - ${seanceActuelle!["fin"]}",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.class_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            "Aucune classe assignée",
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildClasseCard(Map<String, dynamic> classe) {
    final nomClasse = classe["nom"];
    final etudiants = classe["etudiants"] as List;
    final total = etudiants.length;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrirSeances(classe),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFB721D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.school, color: Color(0xFFFB721D), size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nomClasse,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          "$total élève${total > 1 ? 's' : ''}",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFFFB721D)),
                ],
              ),
              const Divider(height: 24),
              // Afficher les séances de la journée
              Text(
                "Séances disponibles",
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SeanceConfig.seances.map((seance) {
                  final String seanceId = seance["id"].toString();
                  final isActive = seanceActuelle?["id"]?.toString() == seanceId;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFFFB721D) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      seanceId,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey[700],
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _ouvrirSeances(Map<String, dynamic> classe) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClasseSeancesPage(
          classeId: classe["id"],
          nomClasse: classe["nom"],
          etudiants: List<Map<String, dynamic>>.from(classe["etudiants"]),
          enseignantId: enseignantId!,
          enseignantNom: enseignantNom ?? "Enseignant",
        ),
      ),
    );
  }
}

// =============================================================================
// PAGE DES SÉANCES D'UNE CLASSE
// =============================================================================
class ClasseSeancesPage extends StatefulWidget {
  final String classeId;
  final String nomClasse;
  final List<Map<String, dynamic>> etudiants;
  final String enseignantId;
  final String enseignantNom;

  const ClasseSeancesPage({
    required this.classeId,
    required this.nomClasse,
    required this.etudiants,
    required this.enseignantId,
    required this.enseignantNom,
    super.key,
  });

  @override
  State<ClasseSeancesPage> createState() => _ClasseSeancesPageState();
}

class _ClasseSeancesPageState extends State<ClasseSeancesPage> {
  final DatabaseReference db = FirebaseDatabase.instance.ref();
  final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  Map<String, dynamic>? seanceActuelle;
  Map<String, Map<String, int>> statsParSeance = {}; // S1 -> {presents: x, absents: y}
  Map<String, Map<String, dynamic>> configSeances = {}; // Config modifiée par l'enseignant
  
  final List<StreamSubscription> _subscriptions = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    seanceActuelle = SeanceConfig.getSeanceActuelle();
    _chargerStats();
    _chargerConfigSeances();
    
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          seanceActuelle = SeanceConfig.getSeanceActuelle();
        });
      }
    });
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _chargerStats() {
    // Écouter les pointages pour chaque séance
    final sub = db.child("pointages_seances/$today/${widget.classeId}").onValue.listen((event) {
      if (!mounted) return;

      Map<String, Map<String, int>> tempStats = {};

      for (var seance in SeanceConfig.seances) {
        String seanceId = seance["id"].toString();
        tempStats[seanceId] = {"presents": 0, "retards": 0, "absents": widget.etudiants.length};
      }

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;

        for (var seanceEntry in data.entries) {
          String seanceId = seanceEntry.key.toString();
          if (seanceEntry.value is Map) {
            int presents = 0;
            int retards = 0;

            (seanceEntry.value as Map).forEach((etuId, pointage) {
              if (pointage is Map) {
                if (pointage["present"] == true) {
                  if (pointage["retard"] == true) {
                    retards++;
                  } else {
                    presents++;
                  }
                }
              }
            });

            tempStats[seanceId] = {
              "presents": presents,
              "retards": retards,
              "absents": widget.etudiants.length - presents - retards,
            };
          }
        }
      }

      setState(() {
        statsParSeance = tempStats;
      });
    });

    _subscriptions.add(sub);
  }

  void _chargerConfigSeances() {
    final sub = db.child("config_seances/$today/${widget.classeId}").onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;
        Map<String, Map<String, dynamic>> temp = {};
        
        data.forEach((seanceId, config) {
          if (config is Map) {
            temp[seanceId.toString()] = Map<String, dynamic>.from(config);
          }
        });

        setState(() {
          configSeances = temp;
        });
      }
    });

    _subscriptions.add(sub);
  }

  void _modifierHeureSeance(Map<String, dynamic> seance) async {
    final String seanceId = seance["id"].toString();
    final config = configSeances[seanceId] ?? {};
    
    TimeOfDay? heureDebut = TimeOfDay(
      hour: int.parse((config["heure_debut"] ?? seance["debut"]).split(":")[0]),
      minute: int.parse((config["heure_debut"] ?? seance["debut"]).split(":")[1]),
    );

    final nouvelleHeure = await showTimePicker(
      context: context,
      initialTime: heureDebut,
      helpText: "Nouvelle heure de début",
    );

    if (nouvelleHeure != null) {
      final heureStr = "${nouvelleHeure.hour.toString().padLeft(2, '0')}:${nouvelleHeure.minute.toString().padLeft(2, '0')}";
      final retardStr = "${nouvelleHeure.hour.toString().padLeft(2, '0')}:${(nouvelleHeure.minute + 10).toString().padLeft(2, '0')}";

      await db.child("config_seances/$today/${widget.classeId}/$seanceId").update({
        "heure_debut": heureStr,
        "retard_limite": retardStr,
        "modifie_par": widget.enseignantId,
        "timestamp": DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Heure de $seanceId modifiée à $heureStr"),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _toggleAccepterRetardataires(String seanceId, bool actuel) async {
    await db.child("config_seances/$today/${widget.classeId}/$seanceId").update({
      "accepter_retardataires": !actuel,
      "modifie_par": widget.enseignantId,
      "timestamp": DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nomClasse),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // En-tête avec info classe
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFFB721D).withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.school, color: Color(0xFFFB721D)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${widget.etudiants.length} élèves dans cette classe",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Séances du ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Liste des séances
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: SeanceConfig.seances.length,
              itemBuilder: (_, i) => _buildSeanceCard(SeanceConfig.seances[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeanceCard(Map<String, dynamic> seance) {
    final String seanceId = seance["id"].toString();
    final isActive = seanceActuelle?["id"]?.toString() == seanceId;
    final stats = statsParSeance[seanceId] ?? {"presents": 0, "retards": 0, "absents": widget.etudiants.length};
    final config = configSeances[seanceId];
    
    // Heure personnalisée ou par défaut
    final heureDebut = config?["heure_debut"] ?? seance["debut"];
    final heureFin = seance["fin"];
    final accepterRetardataires = config?["accepter_retardataires"] ?? true;
    
    // Vérifier si la séance est passée ou future
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final debutParts = seance["debut"].toString().split(":");
    final finParts = seance["fin"].toString().split(":");
    final debutMinutes = int.parse(debutParts[0]) * 60 + int.parse(debutParts[1]);
    final finMinutes = int.parse(finParts[0]) * 60 + int.parse(finParts[1]);
    
    final bool isPassed = currentMinutes >= finMinutes; // Séance terminée
    final bool isFuture = currentMinutes < debutMinutes; // Séance pas encore commencée
    final bool canAccess = isActive || isPassed; // Peut accéder si active ou passée (pour voir les stats)

    return Opacity(
      opacity: isFuture ? 0.5 : 1.0, // Griser les séances futures
      child: Card(
        elevation: isActive ? 8 : 2,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isActive 
              ? const BorderSide(color: Color(0xFFFB721D), width: 2)
              : isPassed
                  ? BorderSide(color: Colors.grey[400]!, width: 1)
                  : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canAccess 
              ? () => _ouvrirPointageSeance(seance)
              : () {
                  // Afficher message si séance future
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("⏳ La séance $seanceId n'a pas encore commencé"),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? const Color(0xFFFB721D) 
                            : isPassed 
                                ? Colors.grey[400]
                                : Colors.grey[300],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        seanceId,
                        style: TextStyle(
                          color: isActive ? Colors.white : (isPassed ? Colors.white : Colors.grey[700]),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$heureDebut - $heureFin",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: isFuture ? Colors.grey : Colors.black,
                            ),
                          ),
                          if (config != null && config["heure_debut"] != null)
                            Text(
                              "⚠️ Heure modifiée",
                              style: TextStyle(color: Colors.orange[700], fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    // Badge de statut
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "EN COURS",
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    else if (isPassed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "TERMINÉE",
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "À VENIR",
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 24),
                // Statistiques
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBadge("Présents", stats["presents"] ?? 0, Colors.green),
                    _statBadge("Retards", stats["retards"] ?? 0, Colors.orange),
                    _statBadge("Absents", stats["absents"] ?? 0, Colors.red),
                  ],
                ),
                // Options enseignant (seulement pour séance active)
                if (isActive) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time, size: 18),
                          label: const Text("Modifier l'heure"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFB721D),
                          ),
                          onPressed: () => _modifierHeureSeance(seance),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(
                            accepterRetardataires ? Icons.lock_open : Icons.lock,
                            size: 18,
                          ),
                          label: Text(accepterRetardataires ? "Fermer porte" : "Ouvrir porte"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accepterRetardataires ? Colors.red : Colors.green,
                          ),
                          onPressed: () => _toggleAccepterRetardataires(seanceId, accepterRetardataires),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statBadge(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            "$value",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      ],
    );
  }

  void _ouvrirPointageSeance(Map<String, dynamic> seance) {
    final String seanceId = seance["id"].toString();
    final config = configSeances[seanceId];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PointageSeancePage(
          classeId: widget.classeId,
          nomClasse: widget.nomClasse,
          seanceId: seanceId,
          seanceDebut: config?["heure_debut"]?.toString() ?? seance["debut"].toString(),
          seanceFin: seance["fin"].toString(),
          retardLimite: config?["retard_limite"]?.toString() ?? seance["retard_limite"].toString(),
          etudiants: widget.etudiants,
          enseignantId: widget.enseignantId,
          enseignantNom: widget.enseignantNom,
          accepterRetardataires: config?["accepter_retardataires"] ?? true,
        ),
      ),
    );
  }
}

