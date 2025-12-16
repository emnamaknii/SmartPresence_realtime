// lib/screens/enseignant_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'pointage_classe_page.dart';

class EnseignantPage extends StatefulWidget {
  const EnseignantPage({super.key}); // plus de enseignantId !

  @override
  State<EnseignantPage> createState() => _EnseignantPageState();
}

class _EnseignantPageState extends State<EnseignantPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final DatabaseReference db = FirebaseDatabase.instance.ref();
  final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  List<Map<String, dynamic>> classes = [];
  bool isLoading = true;
  String? enseignantId;
  
  // Stocker les abonnements pour les annuler dans dispose()
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, "/login");
      });
    } else {
      chargerTout();
    }
  }
  
  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> chargerTout() async {
    // 1. Trouver l'ID ENSxxx via le uid
    final snap = await db.child("enseignants").orderByChild("uid").equalTo(user!.uid).once();
    if (!snap.snapshot.exists) {
      FirebaseAuth.instance.signOut();
      return;
    }
    enseignantId = (snap.snapshot.value as Map).keys.first as String;

    // 2. Écouter ses classes en temps réel
    final classesSub = db.child("enseignants/$enseignantId/classes").onValue.listen((event) async {
      if (!mounted) return;
      
      if (event.snapshot.value == null) {
        setState(() {
          classes = [];
          isLoading = false;
        });
        return;
      }

      final Map classesMap = event.snapshot.value as Map;
      List<Map<String, dynamic>> temp = [];

      for (String classeId in classesMap.keys) {
        // Récupérer les infos de la classe
        final classeSnap = await db.child("classes/$classeId").once();
        if (!classeSnap.snapshot.exists) continue;
        final classeData = classeSnap.snapshot.value as Map;
        final nomClasse = classeData["nom"] ?? "Classe";

        // Récupérer les étudiants de la classe
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
            "present": false, // Sera mis à jour par le listener de pointages
          });
        }

        etudiants.sort((a, b) => a["nom"].compareTo(b["nom"]));

        temp.add({
          "id": classeId,
          "nom": nomClasse,
          "etudiants": etudiants,
        });
      }

      temp.sort((a, b) => a["nom"].compareTo(b["nom"]));

      if (mounted) {
        setState(() {
          classes = temp;
          isLoading = false;
        });
        
        // Écouter les pointages pour chaque classe
        _ecouterPointages();
      }
    });
    
    _subscriptions.add(classesSub);
  }
  
  void _ecouterPointages() {
    // Écouter les pointages du jour pour toutes les classes
    final pointagesSub = db.child("pointages/$today").onValue.listen((event) {
      if (!mounted) return;
      
      Map<dynamic, dynamic>? pointagesData;
      if (event.snapshot.exists && event.snapshot.value != null) {
        pointagesData = event.snapshot.value as Map<dynamic, dynamic>;
      }
      
      setState(() {
        for (var classe in classes) {
          String classeId = classe["id"];
          List<Map<String, dynamic>> etudiants = classe["etudiants"];
          
          for (var etu in etudiants) {
            String etuId = etu["id"];
            
            // Vérifier si l'étudiant a un pointage aujourd'hui pour cette classe
            if (pointagesData != null &&
                pointagesData[classeId] != null &&
                pointagesData[classeId][etuId] != null) {
              final pointage = pointagesData[classeId][etuId];
              if (pointage is Map) {
                etu["present"] = pointage["present"] == true || pointage["retard"] == true;
              } else {
                etu["present"] = pointage == true;
              }
            } else {
              etu["present"] = false;
            }
          }
        }
      });
    });
    
    _subscriptions.add(pointagesSub);
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
            child: const Text("Oui"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Pointage du ${DateFormat('dd/MM/yyyy').format(DateTime.now())}"),
        backgroundColor: const Color(0xFFFB721D),
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _deconnexion),
          IconButton(
            icon: const Icon(Icons.fingerprint, size: 34, color: Colors.white),
            onPressed: () async {
              try {
                await http.get(Uri.parse("http://172.20.10.6/mode?m=detection"));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Mode pointage activé !"), backgroundColor: Color(0xFFFB721D)),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e")));
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : classes.isEmpty
          ? const Center(child: Text("Aucune classe assignée"))
          : ListView.builder(
        itemCount: classes.length,
        itemBuilder: (_, i) {
          final cls = classes[i];
          final presents = cls["etudiants"].where((e) => e["present"] == true).length;
          final total = cls["etudiants"].length;

          return Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFFB721D),
                child: Text("$presents/$total", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(cls["nom"], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("$presents présents • ${total - presents} absents"),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PointageClassePage(
                    classeId: cls["id"],
                    nomClasse: cls["nom"],
                    etudiants: List.from(cls["etudiants"]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}