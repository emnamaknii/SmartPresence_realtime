import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class AdminRapportsPage extends StatefulWidget {
  const AdminRapportsPage({super.key});

  @override
  State<AdminRapportsPage> createState() => _AdminRapportsPageState();
}

class _AdminRapportsPageState extends State<AdminRapportsPage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  
  List<String> dates = [];
  bool isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _chargerDates();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _chargerDates() {
    // Écouter RAPPORTS_SEANCES (nouveau format avec séances)
    _subscription = dbRef.child("rapports_seances").onValue.listen((event) {
      if (!mounted) return;
      
      List<String> temp = [];
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        temp = data.keys.map((e) => e.toString()).toList();
        temp.sort((a, b) => b.compareTo(a)); // Plus récent en premier
      }
      
      setState(() {
        dates = temp;
        isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📋 Rapports de Présence"),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : dates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        "Aucun rapport disponible",
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Les rapports apparaîtront ici\naprès validation par les enseignants",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: dates.length,
                  itemBuilder: (context, index) {
                    String date = dates[index];
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFB721D).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            color: Color(0xFFFB721D),
                          ),
                        ),
                        title: Text(
                          _formatDate(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Text(date),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RapportsParEnseignantPage(date: date),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(String date) {
    try {
      final dt = DateTime.parse(date);
      return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(dt);
    } catch (_) {
      return date;
    }
  }
}

// =============================================================================
// PAGE DES RAPPORTS PAR ENSEIGNANT - Liste les enseignants qui ont validé
// =============================================================================
class RapportsParEnseignantPage extends StatefulWidget {
  final String date;
  const RapportsParEnseignantPage({required this.date, super.key});

  @override
  State<RapportsParEnseignantPage> createState() => _RapportsParEnseignantPageState();
}

class _RapportsParEnseignantPageState extends State<RapportsParEnseignantPage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  
  List<Map<String, dynamic>> enseignants = [];
  Map<String, String> enseignantsNoms = {}; // Cache des noms
  bool isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _chargerEnseignantsNoms();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // Charger d'abord tous les noms des enseignants
  Future<void> _chargerEnseignantsNoms() async {
    try {
      final snap = await dbRef.child("enseignants").get();
      if (snap.exists && snap.value != null) {
        final data = snap.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          if (value is Map) {
            String nom = "${value["prenom"] ?? ""} ${value["nom"] ?? ""}".trim();
            enseignantsNoms[key.toString()] = nom.isNotEmpty ? nom : "Enseignant";
          }
        });
      }
    } catch (e) {
      debugPrint("❌ Erreur chargement noms enseignants: $e");
    }
    
    _chargerRapports();
  }

  void _chargerRapports() {
    // Nouveau format: rapports_seances/{date}/{enseignantId}/{classeId}/{seanceId}
    _subscription = dbRef.child("rapports_seances/${widget.date}").onValue.listen((event) {
      if (!mounted) return;
      
      List<Map<String, dynamic>> temp = [];
      
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        
        debugPrint("📊 Données rapports_seances pour ${widget.date}: ${data.keys.toList()}");
        
        // Chaque clé est un enseignant ID (ENS001, ENS002, etc.)
        for (var entry in data.entries) {
          String enseignantId = entry.key.toString();
          var classesData = entry.value;
          
          if (classesData is Map) {
            // Compter les classes et séances
            int nbClasses = 0;
            int nbSeances = 0;
            int totalPresents = 0;
            int totalAbsents = 0;
            int totalRetards = 0;
            int totalEtudiants = 0;
            
            // Parcourir les classes
            classesData.forEach((classeId, seancesData) {
              if (seancesData is Map) {
                nbClasses++;
                
                // Parcourir les séances de cette classe
                seancesData.forEach((seanceId, rapport) {
                  if (rapport is Map) {
                    nbSeances++;
                    totalPresents += _toInt(rapport["presents"]);
                    totalAbsents += _toInt(rapport["absents"]);
                    totalRetards += _toInt(rapport["retards"]);
                    totalEtudiants += _toInt(rapport["total_etudiants"]);
                  }
                });
              }
            });
            
            // Nom de l'enseignant
            String enseignantNom = enseignantsNoms[enseignantId] ?? enseignantId;
            
            temp.add({
              "enseignantId": enseignantId,
              "enseignantNom": enseignantNom,
              "nbClasses": nbClasses,
              "nbSeances": nbSeances,
              "totalPresents": totalPresents,
              "totalAbsents": totalAbsents,
              "totalRetards": totalRetards,
              "totalEtudiants": totalEtudiants,
            });
          }
        }
      }
      
      if (mounted) {
        setState(() {
          enseignants = temp;
          isLoading = false;
        });
      }
    });
  }
  
  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Rapports du ${widget.date}"),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : enseignants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text("Aucun rapport pour cette date"),
                      const SizedBox(height: 8),
                      Text(
                        "Les enseignants n'ont pas encore validé",
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: enseignants.length,
                  itemBuilder: (ctx, i) {
                    final ens = enseignants[i];
                    bool ancienFormat = ens["ancienFormat"] == true;
                    
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RapportsClassesEnseignantPage(
                                date: widget.date,
                                enseignantId: ens["enseignantId"],
                                enseignantNom: ens["enseignantNom"],
                                ancienFormat: ancienFormat,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: const Color(0xFFFB721D),
                                    child: Text(
                                      ens["enseignantNom"].toString().isNotEmpty 
                                          ? ens["enseignantNom"][0].toUpperCase()
                                          : "?",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ens["enseignantNom"],
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          ens["enseignantId"],
                                          style: TextStyle(color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      "${ens["nbSeances"] ?? ens["nbClasses"]} séance(s)",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _miniStat("Total", ens["totalEtudiants"], Colors.blue),
                                  _miniStat("Présents", ens["totalPresents"], Colors.green),
                                  _miniStat("Absents", ens["totalAbsents"], Colors.red),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
  
  Widget _miniStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          "$value",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }
}

// =============================================================================
// PAGE DES CLASSES D'UN ENSEIGNANT - Liste les classes validées par l'enseignant
// =============================================================================
class RapportsClassesEnseignantPage extends StatefulWidget {
  final String date;
  final String enseignantId;
  final String enseignantNom;
  final bool ancienFormat;

  const RapportsClassesEnseignantPage({
    required this.date,
    required this.enseignantId,
    required this.enseignantNom,
    this.ancienFormat = false,
    super.key,
  });

  @override
  State<RapportsClassesEnseignantPage> createState() => _RapportsClassesEnseignantPageState();
}

class _RapportsClassesEnseignantPageState extends State<RapportsClassesEnseignantPage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  
  List<Map<String, dynamic>> classes = [];
  bool isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _chargerClasses();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _chargerClasses() {
    if (widget.ancienFormat) {
      // Ancien format: chercher dans rapports/date/CLS...
      _chargerClassesAncienFormat();
    } else {
      // Nouveau format: rapports/date/enseignantId/CLS...
      _chargerClassesNouveauFormat();
    }
  }
  
  void _chargerClassesNouveauFormat() {
    // Nouveau format: rapports_seances/{date}/{enseignantId}/{classeId}/{seanceId}
    _subscription = dbRef
        .child("rapports_seances/${widget.date}/${widget.enseignantId}")
        .onValue
        .listen((event) {
      if (!mounted) return;
      
      List<Map<String, dynamic>> temp = [];
      
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        
        // Parcourir les classes
        data.forEach((classeId, seancesData) {
          if (seancesData is Map) {
            // Parcourir les séances de cette classe
            seancesData.forEach((seanceId, rapport) {
              if (rapport is Map) {
                temp.add({
                  "classeId": classeId.toString(),
                  "seanceId": seanceId.toString(),
                  "classe": rapport["classe"] ?? "Classe inconnue",
                  "seance": rapport["seance"] ?? seanceId.toString(),
                  "heure_debut": rapport["heure_debut"] ?? "",
                  "heure_fin": rapport["heure_fin"] ?? "",
                  "total_etudiants": rapport["total_etudiants"] ?? 0,
                  "presents": rapport["presents"] ?? 0,
                  "retards": rapport["retards"] ?? 0,
                  "absents": rapport["absents"] ?? 0,
                  "emails_envoyes": rapport["emails_envoyes"] ?? 0,
                  "timestamp": rapport["timestamp"] ?? "",
                });
              }
            });
          }
        });
        
        // Trier par classe puis par séance
        temp.sort((a, b) {
          int classeCompare = (a["classe"] ?? "").toString().compareTo((b["classe"] ?? "").toString());
          if (classeCompare != 0) return classeCompare;
          return (a["seanceId"] ?? "").toString().compareTo((b["seanceId"] ?? "").toString());
        });
      }
      
      setState(() {
        classes = temp;
        isLoading = false;
      });
    });
  }
  
  void _chargerClassesAncienFormat() {
    _subscription = dbRef
        .child("rapports/${widget.date}")
        .onValue
        .listen((event) {
      if (!mounted) return;
      
      List<Map<String, dynamic>> temp = [];
      
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        
        data.forEach((key, rapport) {
          if (key.toString().startsWith("CLS") && rapport is Map) {
            // Vérifier si c'est pour cet enseignant
            String rapportEnsId = rapport["enseignant_id"]?.toString() ?? 
                rapport["enseignant"]?.toString() ?? "inconnu";
            
            if (rapportEnsId == widget.enseignantId) {
              temp.add({
                "classeId": key.toString(),
                "classe": rapport["classe"] ?? "Classe inconnue",
                "total_etudiants": rapport["total_etudiants"] ?? 0,
                "presents": rapport["presents"] ?? 0,
                "retards": rapport["retards"] ?? 0,
                "absents": rapport["absents"] ?? 0,
                "emails_envoyes": rapport["emails_envoyes"] ?? 0,
                "timestamp": rapport["timestamp"] ?? "",
              });
            }
          }
        });
      }
      
      setState(() {
        classes = temp;
        isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.enseignantNom),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // En-tête enseignant
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFFB721D).withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.person, color: Color(0xFFFB721D)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Rapports de ${widget.enseignantNom}\n${widget.date}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFB721D),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Liste des classes
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : classes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.class_outlined, size: 60, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            const Text("Aucune classe validée"),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: classes.length,
                        itemBuilder: (ctx, i) {
                          final cls = classes[i];
                          return Card(
                            elevation: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RapportDetailPage(
                                      date: widget.date,
                                      enseignantId: widget.enseignantId,
                                      classeId: cls["classeId"],
                                      classeNom: cls["classe"],
                                      seanceId: cls["seanceId"],
                                      ancienFormat: widget.ancienFormat,
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                cls["classe"] ?? "Classe",
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (cls["seanceId"] != null)
                                                Row(
                                                  children: [
                                                    Container(
                                                      margin: const EdgeInsets.only(top: 4),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        cls["seanceId"],
                                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      "${cls["heure_debut"]} - ${cls["heure_fin"]}",
                                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFB721D),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            "${cls["total_etudiants"]} élèves",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        _statChip("Présents", cls["presents"] ?? 0, Colors.green),
                                        _statChip("Retards", cls["retards"] ?? 0, Colors.orange),
                                        _statChip("Absents", cls["absents"] ?? 0, Colors.red),
                                      ],
                                    ),
                                    const Divider(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "📧 ${cls["emails_envoyes"] ?? 0} email(s) envoyé(s)",
                                          style: TextStyle(color: Colors.grey[600]),
                                        ),
                                        const Row(
                                          children: [
                                            Text("Modifier", style: TextStyle(color: Color(0xFFFB721D))),
                                            Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFFB721D)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            "$value",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }
}

// =============================================================================
// PAGE DÉTAIL DU RAPPORT - L'admin peut modifier les statuts
// =============================================================================
class RapportDetailPage extends StatefulWidget {
  final String date;
  final String enseignantId;
  final String classeId;
  final String classeNom;
  final String? seanceId;
  final bool ancienFormat;

  const RapportDetailPage({
    required this.date,
    required this.enseignantId,
    required this.classeId,
    required this.classeNom,
    this.seanceId,
    this.ancienFormat = false,
    super.key,
  });

  @override
  State<RapportDetailPage> createState() => _RapportDetailPageState();
}

class _RapportDetailPageState extends State<RapportDetailPage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  
  Map<String, dynamic> etudiants = {};
  bool isLoading = true;
  bool hasChanges = false;
  StreamSubscription? _subscription;

  // Chemin vers le rapport selon le format
  String get rapportPath {
    if (widget.seanceId != null) {
      // Nouveau format avec séances
      return "rapports_seances/${widget.date}/${widget.enseignantId}/${widget.classeId}/${widget.seanceId}/details";
    } else if (widget.ancienFormat) {
      return "rapports/${widget.date}/${widget.classeId}/details";
    } else {
      return "rapports/${widget.date}/${widget.enseignantId}/${widget.classeId}/details";
    }
  }
  
  String get rapportBasePath {
    if (widget.seanceId != null) {
      // Nouveau format avec séances
      return "rapports_seances/${widget.date}/${widget.enseignantId}/${widget.classeId}/${widget.seanceId}";
    } else if (widget.ancienFormat) {
      return "rapports/${widget.date}/${widget.classeId}";
    } else {
      return "rapports/${widget.date}/${widget.enseignantId}/${widget.classeId}";
    }
  }
  
  String get pointagePath {
    if (widget.seanceId != null) {
      // Nouveau format avec séances
      return "pointages_seances/${widget.date}/${widget.classeId}/${widget.seanceId}";
    } else {
      return "pointages/${widget.date}/${widget.classeId}";
    }
  }

  @override
  void initState() {
    super.initState();
    _chargerDetails();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _chargerDetails() {
    debugPrint("📖 Chargement détails: $rapportPath");
    
    _subscription = dbRef.child(rapportPath).onValue.listen((event) {
      if (!mounted) return;
      
      if (event.snapshot.exists && event.snapshot.value != null) {
        setState(() {
          etudiants = Map<String, dynamic>.from(event.snapshot.value as Map);
          isLoading = false;
        });
        debugPrint("✅ ${etudiants.length} étudiants chargés");
      } else {
        debugPrint("⚠️ Aucun détail trouvé");
        setState(() {
          etudiants = {};
          isLoading = false;
        });
      }
    });
  }

  void _changerStatut(String etuId, String nouveauStatut) {
    setState(() {
      etudiants[etuId]["present"] = nouveauStatut == "present" || nouveauStatut == "retard";
      etudiants[etuId]["retard"] = nouveauStatut == "retard";
      hasChanges = true;
    });
  }

  Future<void> _sauvegarderModifications() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. Mettre à jour les détails du rapport
      await dbRef.child(rapportPath).set(etudiants);
      debugPrint("✅ Détails rapport mis à jour: $rapportPath");
      
      // 2. Mettre à jour les pointages en temps réel
      for (var entry in etudiants.entries) {
        String etuId = entry.key;
        bool present = entry.value["present"] == true;
        bool retard = entry.value["retard"] == true;
        
        await dbRef.child("$pointagePath/$etuId").update({
          "present": present,
          "retard": retard,
          "manuelle": true,
          "modifie_par_admin": true,
          "heure_modification": DateTime.now().toIso8601String(),
        });
        
        // Aussi mettre à jour le pointage global si on est dans le format séance
        if (widget.seanceId != null) {
          await dbRef.child("pointages/${widget.date}/${widget.classeId}/$etuId").update({
            "present": present,
            "retard": retard,
            "manuelle": true,
            "modifie_par_admin": true,
            "heure_modification": DateTime.now().toIso8601String(),
          });
        }
      }
      debugPrint("✅ Pointages mis à jour");

      // 3. Recalculer les statistiques
      int presents = etudiants.values.where((e) => e["present"] == true && e["retard"] != true).length;
      int retards = etudiants.values.where((e) => e["retard"] == true).length;
      int absents = etudiants.values.where((e) => e["present"] != true).length;

      await dbRef.child(rapportBasePath).update({
        "presents": presents,
        "retards": retards,
        "absents": absents,
        "derniere_modification": DateTime.now().toIso8601String(),
        "modifie_par": "admin",
      });
      debugPrint("✅ Stats mises à jour: $presents présents, $retards retards, $absents absents");

      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Modifications enregistrées !"),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => hasChanges = false);
      }
    } catch (e) {
      debugPrint("❌ Erreur sauvegarde: $e");
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.classeNom;
    if (widget.seanceId != null) {
      title = "${widget.classeNom} - ${widget.seanceId}";
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
        actions: [
          if (hasChanges)
            TextButton.icon(
              onPressed: _sauvegarderModifications,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text("Sauvegarder", style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : etudiants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text("Aucun étudiant dans ce rapport"),
                      const SizedBox(height: 8),
                      Text(
                        "Les détails ne sont pas disponibles",
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // En-tête
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.grey[100],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatBadge(
                            "Présents",
                            etudiants.values.where((e) => e["present"] == true && e["retard"] != true).length,
                            Colors.green,
                          ),
                          _buildStatBadge(
                            "Retards",
                            etudiants.values.where((e) => e["retard"] == true).length,
                            Colors.orange,
                          ),
                          _buildStatBadge(
                            "Absents",
                            etudiants.values.where((e) => e["present"] != true).length,
                            Colors.red,
                          ),
                        ],
                      ),
                    ),
                    // Liste des étudiants
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: etudiants.length,
                        itemBuilder: (ctx, i) {
                          String etuId = etudiants.keys.elementAt(i);
                          var etu = etudiants[etuId];
                          bool present = etu["present"] == true;
                          bool retard = etu["retard"] == true;
                          
                          String statut = retard ? "retard" : (present ? "present" : "absent");
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getColor(statut),
                                child: Icon(_getIcon(statut), color: Colors.white),
                              ),
                              title: Text(
                                "${etu["prenom"] ?? ""} ${etu["nom"] ?? ""}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text("ID: $etuId"),
                              trailing: PopupMenuButton<String>(
                                icon: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _getColor(statut).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _getLabel(statut),
                                        style: TextStyle(
                                          color: _getColor(statut),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Icon(Icons.arrow_drop_down, color: _getColor(statut)),
                                    ],
                                  ),
                                ),
                                onSelected: (value) => _changerStatut(etuId, value),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: "present",
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green),
                                        SizedBox(width: 10),
                                        Text("Présent"),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: "retard",
                                    child: Row(
                                      children: [
                                        Icon(Icons.access_time, color: Colors.orange),
                                        SizedBox(width: 10),
                                        Text("En retard"),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: "absent",
                                    child: Row(
                                      children: [
                                        Icon(Icons.cancel, color: Colors.red),
                                        SizedBox(width: 10),
                                        Text("Absent"),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: hasChanges
          ? Container(
              padding: const EdgeInsets.all(16),
              color: Colors.orange[50],
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Modifications non sauvegardées",
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _sauvegarderModifications,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFB721D),
                    ),
                    child: const Text("Sauvegarder", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          : null,
    );
  }
  
  Widget _buildStatBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$value",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Color _getColor(String statut) {
    switch (statut) {
      case "present": return Colors.green;
      case "retard": return Colors.orange;
      case "absent": return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getIcon(String statut) {
    switch (statut) {
      case "present": return Icons.check_circle;
      case "retard": return Icons.access_time;
      case "absent": return Icons.cancel;
      default: return Icons.help;
    }
  }

  String _getLabel(String statut) {
    switch (statut) {
      case "present": return "Présent";
      case "retard": return "Retard";
      case "absent": return "Absent";
      default: return "?";
    }
  }
}
