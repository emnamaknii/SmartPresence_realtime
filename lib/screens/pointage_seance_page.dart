// lib/screens/pointage_seance_page.dart
// Page de pointage pour une séance spécifique

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class PointageSeancePage extends StatefulWidget {
  final String classeId;
  final String nomClasse;
  final String seanceId;
  final String seanceDebut;
  final String seanceFin;
  final String retardLimite;
  final List<Map<String, dynamic>> etudiants;
  final String enseignantId;
  final String enseignantNom;
  final bool accepterRetardataires;

  const PointageSeancePage({
    required this.classeId,
    required this.nomClasse,
    required this.seanceId,
    required this.seanceDebut,
    required this.seanceFin,
    required this.retardLimite,
    required this.etudiants,
    required this.enseignantId,
    required this.enseignantNom,
    required this.accepterRetardataires,
    super.key,
  });

  @override
  State<PointageSeancePage> createState() => _PointageSeancePageState();
}

class _PointageSeancePageState extends State<PointageSeancePage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  final String aujourdHui = DateFormat('yyyy-MM-dd').format(DateTime.now());

  Map<String, String> statutEtudiants = {}; // etuId -> present/retard/absent
  Map<String, bool> billets = {}; // etuId -> a un billet
  Map<String, String?> heuresPointage = {}; // etuId -> heure de pointage
  
  StreamSubscription? _pointageSubscription;
  StreamSubscription? _billetsSubscription;

  // EmailJS config
  static const String _emailJsServiceId = "service_etudiant";
  static const String _emailJsTemplateId = "template_efwoxjc";
  static const String _emailJsPublicKey = "PnCuvDW0kQBr0U4Kp";

  @override
  void initState() {
    super.initState();
    
    // Initialiser tous comme absent
    for (var etu in widget.etudiants) {
      statutEtudiants[etu["id"].toString()] = "absent";
      heuresPointage[etu["id"].toString()] = null;
    }
    
    _ecouterPointages();
    _ecouterBillets();
  }

  @override
  void dispose() {
    _pointageSubscription?.cancel();
    _billetsSubscription?.cancel();
    super.dispose();
  }

  void _ecouterPointages() {
    final path = "pointages_seances/$aujourdHui/${widget.classeId}/${widget.seanceId}";
    debugPrint("🔥 Écoute: $path");

    _pointageSubscription = dbRef.child(path).onValue.listen((event) {
      if (!mounted) return;

      Map<String, String> nouveauxStatuts = {};
      Map<String, String?> nouvellesHeures = {};
      
      for (var etu in widget.etudiants) {
        nouveauxStatuts[etu["id"].toString()] = "absent";
        nouvellesHeures[etu["id"].toString()] = null;
      }

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;

        data.forEach((key, value) {
          String etuId = key.toString();
          if (value is Map) {
            bool present = value["present"] == true;
            bool retard = value["retard"] == true;
            String? heure = value["heure"]?.toString();

            if (retard) {
              nouveauxStatuts[etuId] = "retard";
            } else if (present) {
              nouveauxStatuts[etuId] = "present";
            }
            nouvellesHeures[etuId] = heure;
          }
        });
      }

      setState(() {
        statutEtudiants = nouveauxStatuts;
        heuresPointage = nouvellesHeures;
      });
    });
  }

  void _ecouterBillets() {
    final path = "billets_presence/$aujourdHui";
    
    _billetsSubscription = dbRef.child(path).onValue.listen((event) {
      if (!mounted) return;

      Map<String, bool> nouveauxBillets = {};

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;

        data.forEach((etuId, billetData) {
          if (billetData is Map && billetData[widget.seanceId] == true) {
            nouveauxBillets[etuId.toString()] = true;
          }
        });
      }

      setState(() {
        billets = nouveauxBillets;
      });
    });
  }

  Future<void> _changerStatut(String etuId, String nouveauStatut) async {
    setState(() {
      statutEtudiants[etuId] = nouveauStatut;
    });

    final data = {
      "present": nouveauStatut == "present" || nouveauStatut == "retard",
      "retard": nouveauStatut == "retard",
      "manuelle": true,
      "heure": DateTime.now().toIso8601String(),
      "seance": widget.seanceId,
    };

    await dbRef.child("pointages_seances/$aujourdHui/${widget.classeId}/${widget.seanceId}/$etuId").set(data);
    
    // Aussi mettre à jour le pointage global pour la journée
    await dbRef.child("pointages/$aujourdHui/${widget.classeId}/$etuId").set(data);
  }

  Future<bool> _envoyerEmailParent({
    required String emailParent,
    required String nomEtudiant,
    required String prenomEtudiant,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("https://api.emailjs.com/api/v1.0/email/send"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "service_id": _emailJsServiceId,
          "template_id": _emailJsTemplateId,
          "user_id": _emailJsPublicKey,
          "template_params": {
            "to_email": emailParent,
            "to_name": "Parent",
            "from_name": "SmartPresence",
            "student_name": "$prenomEtudiant $nomEtudiant",
            "class_name": widget.nomClasse,
            "date": aujourdHui,
            "message": "Nous vous informons que votre enfant $prenomEtudiant $nomEtudiant "
                "de la classe ${widget.nomClasse} était absent(e) lors de la séance ${widget.seanceId} "
                "(${widget.seanceDebut} - ${widget.seanceFin}) le $aujourdHui.",
          },
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Erreur email: $e");
      return false;
    }
  }

  Future<void> _validerSeance() async {
    // Récupérer les absents
    List<Map<String, dynamic>> etudiantsAbsents = [];

    for (var etu in widget.etudiants) {
      String etuId = etu["id"].toString();
      if (statutEtudiants[etuId] == "absent") {
        etudiantsAbsents.add(etu);
      }
    }

    // Compter les stats
    int presents = statutEtudiants.values.where((s) => s == "present").length;
    int retards = statutEtudiants.values.where((s) => s == "retard").length;
    int absents = etudiantsAbsents.length;

    // Confirmation
    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("📋 Valider ${widget.seanceId}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Classe: ${widget.nomClasse}"),
              Text("Séance: ${widget.seanceDebut} - ${widget.seanceFin}"),
              const Divider(),
              Text("✅ Présents: $presents"),
              Text("⏰ Retards: $retards"),
              Text("❌ Absents: $absents"),
              if (etudiantsAbsents.isNotEmpty) ...[
                const Divider(),
                Text("${etudiantsAbsents.length} email(s) seront envoyés aux parents des absents"),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB721D)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Valider", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmation != true) return;

    // Afficher loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Validation en cours..."),
          ],
        ),
      ),
    );

    int emailsEnvoyes = 0;
    int emailsEchoues = 0;

    try {
      // Envoyer les emails aux parents des absents
      for (var etu in etudiantsAbsents) {
        String? emailParent = etu["email_parent"];
        if (emailParent != null && emailParent.isNotEmpty) {
          bool success = await _envoyerEmailParent(
            emailParent: emailParent,
            nomEtudiant: etu["nom"],
            prenomEtudiant: etu["prenom"],
          );

          if (success) {
            emailsEnvoyes++;
          } else {
            emailsEchoues++;
          }

          // Enregistrer la notification
          await dbRef.child("notifications_seances/$aujourdHui/${widget.classeId}/${widget.seanceId}/${etu["id"]}").set({
            "email_parent": emailParent,
            "nom": etu["nom"],
            "prenom": etu["prenom"],
            "envoye": success,
            "timestamp": DateTime.now().toIso8601String(),
          });
        }
      }

      // Sauvegarder le rapport de séance
      Map<String, dynamic> detailsRapport = {};
      for (var etu in widget.etudiants) {
        String etuId = etu["id"].toString();
        String statut = statutEtudiants[etuId] ?? "absent";

        detailsRapport[etuId] = {
          "nom": etu["nom"],
          "prenom": etu["prenom"],
          "present": statut == "present" || statut == "retard",
          "retard": statut == "retard",
          "heure": heuresPointage[etuId],
        };
      }

      await dbRef.child("rapports_seances/$aujourdHui/${widget.enseignantId}/${widget.classeId}/${widget.seanceId}").set({
        "classe": widget.nomClasse,
        "seance": widget.seanceId,
        "heure_debut": widget.seanceDebut,
        "heure_fin": widget.seanceFin,
        "enseignant_id": widget.enseignantId,
        "enseignant_nom": widget.enseignantNom,
        "timestamp": DateTime.now().toIso8601String(),
        "total_etudiants": widget.etudiants.length,
        "presents": presents,
        "retards": retards,
        "absents": absents,
        "emails_envoyes": emailsEnvoyes,
        "details": detailsRapport,
      });

      // Sauvegarder la validation
      await dbRef.child("validations_seances/$aujourdHui/${widget.classeId}/${widget.seanceId}").set({
        "timestamp": DateTime.now().toIso8601String(),
        "classe": widget.nomClasse,
        "enseignant_id": widget.enseignantId,
        "absents": absents,
        "emails_envoyes": emailsEnvoyes,
      });

      if (mounted) Navigator.pop(context); // Fermer loader

      // Afficher résultat
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text("Validé !"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("✅ Séance ${widget.seanceId} validée"),
                Text("📧 $emailsEnvoyes email(s) envoyé(s)"),
                if (emailsEchoues > 0)
                  Text("❌ $emailsEchoues échec(s)", style: const TextStyle(color: Colors.red)),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context); // Retour à la liste des séances
                },
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
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
    int presents = statutEtudiants.values.where((s) => s == "present").length;
    int retards = statutEtudiants.values.where((s) => s == "retard").length;
    int absents = statutEtudiants.values.where((s) => s == "absent").length;

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.nomClasse} - ${widget.seanceId}"),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // En-tête séance
          Container(
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      "${widget.seanceDebut} - ${widget.seanceFin}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Retard limite: ${widget.retardLimite}",
                  style: const TextStyle(color: Colors.white70),
                ),
                if (!widget.accepterRetardataires)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "🔒 Porte fermée aux retardataires",
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBox("Présents", presents, Colors.green),
                    _statBox("Retards", retards, Colors.orange),
                    _statBox("Absents", absents, Colors.red),
                  ],
                ),
              ],
            ),
          ),
          // Liste des étudiants
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.etudiants.length,
              itemBuilder: (ctx, i) {
                var etu = widget.etudiants[i];
                String etuId = etu["id"].toString();
                String statut = statutEtudiants[etuId] ?? "absent";
                bool aBillet = billets[etuId] == true;
                String? heure = heuresPointage[etuId];

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: _getColor(statut),
                          child: Icon(_getIcon(statut), color: Colors.white),
                        ),
                        if (aBillet)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.verified, color: Colors.white, size: 12),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      "${etu["prenom"]} ${etu["nom"]}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("ID: ${etu["empreinte_id"]}"),
                        if (heure != null)
                          Text(
                            "Pointé à: ${_formatHeure(heure)}",
                            style: const TextStyle(color: Colors.green, fontSize: 11),
                          ),
                        if (aBillet)
                          const Text(
                            "🎫 Billet de présence",
                            style: TextStyle(color: Colors.blue, fontSize: 11),
                          ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getColor(statut).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getLabel(statut),
                          style: TextStyle(
                            color: _getColor(statut),
                            fontWeight: FontWeight.bold,
                          ),
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
          // Bouton validation
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB721D),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _validerSeance,
                label: Text(
                  "Valider ${widget.seanceId}",
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            "$value",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
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

  String _formatHeure(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return isoString;
    }
  }
}


