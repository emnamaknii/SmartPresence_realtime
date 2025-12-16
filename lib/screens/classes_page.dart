import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class ClassePage extends StatefulWidget {
  final String classeId;
  final String classeNom;

  ClassePage({required this.classeId, required this.classeNom});

  @override
  _ClassePageState createState() => _ClassePageState();
}

class _ClassePageState extends State<ClassePage> {
  final dbRef = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> etudiants = [];
  Map<String, String> presences = {}; // Changé en String pour gérer present/retard/absent
  String dateDuJour = DateTime.now().toIso8601String().split("T")[0];

  // Liste des abonnements pour les annuler dans dispose()
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    listenEtudiants();
    listenPresences();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  // 🔥 Mise à jour en temps réel des étudiants
  void listenEtudiants() {
    final sub = dbRef.child("classes/${widget.classeId}/etudiants").onValue.listen((event) async {
      if (!mounted) return;

      if (!event.snapshot.exists) {
        setState(() => etudiants = []);
        return;
      }

      Map map = event.snapshot.value as Map;
      List<Map<String, dynamic>> temp = [];

      for (var entry in map.entries) {
        String id = entry.key;
        final snap = await dbRef.child("etudiants/$id").get();
        if (snap.exists) {
          Map data = snap.value as Map;
          temp.add({
            "id": id,
            "nom": data["nom"] ?? "",
            "prenom": data["prenom"] ?? "",
            "email_parent": data["email_parent"] ?? "",
            "empreinte_id": data["empreinte_id"] ?? 0,
          });
        }
      }

      temp.sort((a, b) => a["nom"].compareTo(b["nom"]));

      if (mounted) {
        setState(() => etudiants = temp);
      }
    });

    _subscriptions.add(sub);
  }

  // 🔥 Mise à jour en temps réel des présences - CORRIGÉ
  void listenPresences() {
    // ✅ Chemin correct : pointages/$date/$classeId (et non presences/$classeId)
    final sub = dbRef.child("pointages/$dateDuJour/${widget.classeId}").onValue.listen((event) {
      if (!mounted) return;

      Map<String, String> temp = {};

      // Si la branche n'existe pas → tous absents
      if (!event.snapshot.exists || event.snapshot.value == null) {
        setState(() => presences = temp);
        return;
      }

      // Structure: pointages/$date/$classeId/$etuId = { "present": true, "retard": false, ... }
      var data = event.snapshot.value as Map;

      data.forEach((etuId, pointageData) {
        if (pointageData is Map) {
          bool present = pointageData["present"] == true;
          bool retard = pointageData["retard"] == true;

          if (retard) {
            temp[etuId as String] = "retard";
          } else if (present) {
            temp[etuId as String] = "present";
          } else {
            temp[etuId as String] = "absent";
          }
        }
      });

      setState(() => presences = temp);
    });

    _subscriptions.add(sub);
  }

  int totalPresents() => presences.values.where((s) => s == "present" || s == "retard").length;
  int totalAbsents() => etudiants.length - totalPresents();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classeNom),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          // ---- STAT ----
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.green[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat("Total", etudiants.length, Colors.blue),
                _stat("Présents", totalPresents(), Colors.green),
                _stat("Absents", totalAbsents(), Colors.red),
              ],
            ),
          ),
          // ---- Date ----
          Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "📅 Date : $dateDuJour",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          // ---- Liste étudiants ----
          Expanded(
            child: ListView.builder(
              itemCount: etudiants.length,
              itemBuilder: (_, i) {
                var e = etudiants[i];
                String statut = presences[e["id"]] ?? "absent";
                bool isPresent = statut == "present" || statut == "retard";

                return Card(
                  color: isPresent ? Colors.green[50] : Colors.white,
                  margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getStatutColor(statut),
                      child: Icon(_getStatutIcon(statut), color: Colors.white),
                    ),
                    title: Text("${e["nom"]} ${e["prenom"]}"),
                    subtitle: Text("Email: ${e["email"]}"),
                    trailing: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatutColor(statut),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getStatutLabel(statut),
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.green,
        icon: Icon(Icons.fingerprint),
        label: Text("Activer pointage"),
        onPressed: () async {
          try {
            await http.get(Uri.parse("http://172.20.10.6/mode?m=detection"));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Mode pointage activé")),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Erreur : $e")),
            );
          }
        },
      ),
    );
  }

  Color _getStatutColor(String statut) {
    switch (statut) {
      case "present":
        return Colors.green;
      case "retard":
        return Colors.orange;
      case "absent":
      default:
        return Colors.red;
    }
  }

  IconData _getStatutIcon(String statut) {
    switch (statut) {
      case "present":
        return Icons.check;
      case "retard":
        return Icons.access_time;
      case "absent":
      default:
        return Icons.close;
    }
  }

  String _getStatutLabel(String statut) {
    switch (statut) {
      case "present":
        return "PRÉSENT";
      case "retard":
        return "EN RETARD";
      case "absent":
      default:
        return "ABSENT";
    }
  }

  Widget _stat(String label, int value, Color c) {
    return Column(
      children: [
        Text(
          "$value",
          style: TextStyle(color: c, fontSize: 30, fontWeight: FontWeight.bold),
        ),
        Text(label),
      ],
    );
  }
}
