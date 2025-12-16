// lib/screens/admin_billets_page.dart
// Page admin pour gérer les billets de présence

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../models/seance_config.dart';

class AdminBilletsPage extends StatefulWidget {
  const AdminBilletsPage({super.key});

  @override
  State<AdminBilletsPage> createState() => _AdminBilletsPageState();
}

class _AdminBilletsPageState extends State<AdminBilletsPage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  final String aujourdHui = DateFormat('yyyy-MM-dd').format(DateTime.now());

  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> etudiantsAbsents = [];
  String? classeSelectionnee;
  String? seanceSelectionnee;
  bool isLoading = true;

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _chargerClasses();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _chargerClasses() async {
    final sub = dbRef.child("classes").onValue.listen((event) {
      if (!mounted) return;

      List<Map<String, dynamic>> temp = [];

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;

        data.forEach((key, value) {
          if (value is Map) {
            temp.add({
              "id": key.toString(),
              "nom": value["nom"] ?? "Classe",
            });
          }
        });
      }

      setState(() {
        classes = temp;
        isLoading = false;
      });
    });

    _subscriptions.add(sub);
  }

  Future<void> _chargerEtudiantsAbsents() async {
    if (classeSelectionnee == null) return;

    setState(() => isLoading = true);

    try {
      // Récupérer la liste des étudiants de la classe
      final classeSnap = await dbRef.child("classes/$classeSelectionnee/etudiants").get();
      if (!classeSnap.exists) {
        setState(() {
          etudiantsAbsents = [];
          isLoading = false;
        });
        return;
      }

      final etuMap = classeSnap.value as Map;
      List<Map<String, dynamic>> absents = [];

      // Séance précédente
      final seanceActuelle = SeanceConfig.getSeanceActuelle();
      String? seancePrecedenteId;

      if (seanceSelectionnee != null) {
        seancePrecedenteId = seanceSelectionnee;
      } else if (seanceActuelle != null) {
        // Trouver la séance précédente
        String seanceActuelleId = seanceActuelle["id"].toString();
        final idx = SeanceConfig.seances.indexWhere((s) => s["id"].toString() == seanceActuelleId);
        if (idx > 0) {
          seancePrecedenteId = SeanceConfig.seances[idx - 1]["id"].toString();
        }
      }

      if (seancePrecedenteId == null) {
        setState(() {
          etudiantsAbsents = [];
          isLoading = false;
        });
        return;
      }

      // Vérifier les pointages de la séance précédente
      final pointagesSnap = await dbRef
          .child("pointages_seances/$aujourdHui/$classeSelectionnee/$seancePrecedenteId")
          .get();

      Map<String, dynamic> pointages = {};
      if (pointagesSnap.exists && pointagesSnap.value != null) {
        pointages = Map<String, dynamic>.from(pointagesSnap.value as Map);
      }

      // Vérifier les billets existants
      final billetsSnap = await dbRef.child("billets_presence/$aujourdHui").get();
      Map<String, dynamic> billetsExistants = {};
      if (billetsSnap.exists && billetsSnap.value != null) {
        billetsExistants = Map<String, dynamic>.from(billetsSnap.value as Map);
      }

      // Pour chaque étudiant, vérifier s'il était absent
      for (String etuId in etuMap.keys) {
        final etuSnap = await dbRef.child("etudiants/$etuId").get();
        if (!etuSnap.exists) continue;

        final etuData = etuSnap.value as Map;
        final pointage = pointages[etuId];

        bool etaitPresent = false;
        if (pointage != null && pointage is Map) {
          etaitPresent = pointage["present"] == true;
        }

        // Vérifier si l'étudiant a déjà un billet pour les séances suivantes
        Map<String, bool> billetsEtu = {};
        if (billetsExistants[etuId] != null && billetsExistants[etuId] is Map) {
          (billetsExistants[etuId] as Map).forEach((seance, value) {
            if (value == true) {
              billetsEtu[seance.toString()] = true;
            }
          });
        }

        // Si absent à la séance précédente
        if (!etaitPresent) {
          absents.add({
            "id": etuId,
            "nom": etuData["nom"] ?? "",
            "prenom": etuData["prenom"] ?? "",
            "empreinte_id": etuData["empreinte_id"] ?? 0,
            "seance_absente": seancePrecedenteId,
            "billets": billetsEtu,
          });
        }
      }

      absents.sort((a, b) => a["nom"].compareTo(b["nom"]));

      setState(() {
        etudiantsAbsents = absents;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Erreur: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _delivrerBillet(String etuId, String seanceId) async {
    try {
      await dbRef.child("billets_presence/$aujourdHui/$etuId/$seanceId").set(true);
      
      // Ajouter les infos du billet
      await dbRef.child("billets_presence/$aujourdHui/$etuId/info").set({
        "delivre_par": "admin",
        "timestamp": DateTime.now().toIso8601String(),
        "classe": classeSelectionnee,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Billet $seanceId délivré !"),
            backgroundColor: Colors.green,
          ),
        );
        _chargerEtudiantsAbsents(); // Recharger la liste
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _retirerBillet(String etuId, String seanceId) async {
    try {
      await dbRef.child("billets_presence/$aujourdHui/$etuId/$seanceId").remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Billet retiré"),
            backgroundColor: Colors.orange,
          ),
        );
        _chargerEtudiantsAbsents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _delivrerBilletDialog(Map<String, dynamic> etudiant) {
    final seanceActuelle = SeanceConfig.getSeanceActuelle();
    
    // Récupérer les billets existants de manière sécurisée
    final billetsData = etudiant["billets"];
    Map<String, bool> billetsEtu = {};
    if (billetsData != null && billetsData is Map) {
      billetsData.forEach((key, value) {
        billetsEtu[key.toString()] = value == true;
      });
    }
    
    // Séances disponibles (à partir de la séance suivante)
    List<Map<String, dynamic>> seancesDisponibles = [];
    bool apresAbsence = false;
    String seanceAbsente = etudiant["seance_absente"]?.toString() ?? "";
    
    for (var seance in SeanceConfig.seances) {
      String seanceId = seance["id"].toString();
      if (seanceId == seanceAbsente) {
        apresAbsence = true;
        continue;
      }
      if (apresAbsence) {
        seancesDisponibles.add(seance);
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("🎫 Billet pour ${etudiant["prenom"]} ${etudiant["nom"]}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Absent(e) à $seanceAbsente",
                style: TextStyle(color: Colors.red[700]),
              ),
              const SizedBox(height: 16),
              const Text("Autoriser l'accès pour :"),
              const SizedBox(height: 8),
              if (seancesDisponibles.isEmpty)
                const Text("Aucune séance disponible", style: TextStyle(color: Colors.grey)),
              ...seancesDisponibles.map((seance) {
                String seanceId = seance["id"].toString();
                bool aBillet = billetsEtu[seanceId] == true;
                bool isActive = seanceActuelle?["id"]?.toString() == seanceId;
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    aBillet ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: aBillet ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    "$seanceId (${seance["debut"]} - ${seance["fin"]})",
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: isActive ? const Text("En cours", style: TextStyle(color: Colors.green)) : null,
                  trailing: aBillet
                      ? TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _retirerBillet(etudiant["id"].toString(), seanceId);
                          },
                          child: const Text("Retirer", style: TextStyle(color: Colors.red)),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFB721D),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _delivrerBillet(etudiant["id"].toString(), seanceId);
                          },
                          child: const Text("Autoriser", style: TextStyle(color: Colors.white)),
                        ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fermer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seanceActuelle = SeanceConfig.getSeanceActuelle();

    return Scaffold(
      appBar: AppBar(
        title: const Text("🎫 Billets de Présence"),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // En-tête
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFFB721D).withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Gestion des autorisations d'accès",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  "Délivrez des billets aux élèves absents pour qu'ils puissent accéder aux séances suivantes",
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                if (seanceActuelle != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Séance actuelle: ${seanceActuelle["id"]} (${seanceActuelle["debut"]} - ${seanceActuelle["fin"]})",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Hors séance",
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Sélection classe et séance
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: classeSelectionnee,
                    decoration: const InputDecoration(
                      labelText: "Classe",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: classes.map<DropdownMenuItem<String>>((c) {
                      return DropdownMenuItem<String>(
                        value: c["id"].toString(),
                        child: Text(c["nom"].toString()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        classeSelectionnee = value;
                        etudiantsAbsents = [];
                      });
                      _chargerEtudiantsAbsents();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: seanceSelectionnee,
                    decoration: const InputDecoration(
                      labelText: "Séance d'absence",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: SeanceConfig.seances.map<DropdownMenuItem<String>>((s) {
                      String seanceId = s["id"].toString();
                      return DropdownMenuItem<String>(
                        value: seanceId,
                        child: Text("$seanceId (${s["debut"]})"),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        seanceSelectionnee = value;
                      });
                      _chargerEtudiantsAbsents();
                    },
                  ),
                ),
              ],
            ),
          ),
          // Liste des absents
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : classeSelectionnee == null
                    ? _buildSelectClasseMessage()
                    : etudiantsAbsents.isEmpty
                        ? _buildNoAbsentsMessage()
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: etudiantsAbsents.length,
                            itemBuilder: (_, i) => _buildEtudiantCard(etudiantsAbsents[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectClasseMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.class_outlined, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            "Sélectionnez une classe",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAbsentsMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 60, color: Colors.green[400]),
          const SizedBox(height: 16),
          Text(
            "Aucun absent pour cette séance !",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            "Tous les élèves étaient présents",
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildEtudiantCard(Map<String, dynamic> etudiant) {
    // Récupérer les billets de manière sécurisée
    final billetsData = etudiant["billets"];
    int nbBillets = 0;
    if (billetsData != null && billetsData is Map) {
      nbBillets = billetsData.values.where((v) => v == true).length;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _delivrerBilletDialog(etudiant),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.red[100],
                child: const Icon(Icons.person_off, color: Colors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${etudiant["prenom"]} ${etudiant["nom"]}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      "Absent à ${etudiant["seance_absente"]}",
                      style: TextStyle(color: Colors.red[700], fontSize: 13),
                    ),
                    if (nbBillets > 0)
                      Text(
                        "🎫 $nbBillets billet(s) délivré(s)",
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFB721D),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text("Billet", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

