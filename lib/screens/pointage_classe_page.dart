// lib/screens/pointage_classes_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PointageClassePage extends StatefulWidget {
  final String classeId;
  final String nomClasse;
  final List<Map<String, dynamic>> etudiants;

  const PointageClassePage({
    required this.classeId,
    required this.nomClasse,
    required this.etudiants,
    super.key,
  });

  @override
  State<PointageClassePage> createState() => _PointageClassePageState();
}

class _PointageClassePageState extends State<PointageClassePage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  final String aujourdHui = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Map<String, String> statutEtudiants = {};
  String? enseignantId;
  String? enseignantNom;

  // Abonnement Firebase unique pour toute la classe
  StreamSubscription? _pointageSubscription;

  @override
  void initState() {
    super.initState();
    
    // Charger les infos de l'enseignant connecté
    _chargerEnseignant();
    
    // Initialiser tous les étudiants comme "absent" par défaut
    for (var etu in widget.etudiants) {
      statutEtudiants[etu["id"].toString()] = "absent";
    }
    
    // Chemin Firebase à écouter
    final String cheminPointage = "pointages/$aujourdHui/${widget.classeId}";
    debugPrint("🔥 Écoute Firebase: $cheminPointage");
    
    // ✅ Écouter TOUT le dossier de pointage de la classe en temps réel
    _pointageSubscription = dbRef
        .child(cheminPointage)
        .onValue
        .listen((event) {
      if (!mounted) return;

      debugPrint("📡 Données reçues de Firebase!");

      // Créer une copie des statuts avec tous les étudiants absents par défaut
      Map<String, String> nouveauxStatuts = {};
    for (var etu in widget.etudiants) {
        nouveauxStatuts[etu["id"].toString()] = "absent";
      }

      // Mettre à jour avec les données de Firebase
      if (event.snapshot.exists && event.snapshot.value != null) {
        debugPrint("📦 Snapshot existe, valeur: ${event.snapshot.value}");
        
        final data = event.snapshot.value;
        
        if (data is Map) {
          data.forEach((key, value) {
            String etuId = key.toString();
            debugPrint("👤 Étudiant trouvé: $etuId");
            
            // Vérifier si cet étudiant est dans la liste de la classe
            bool estDansClasse = widget.etudiants.any((e) => e["id"].toString() == etuId);
            debugPrint("   → Dans cette classe: $estDansClasse");
            
            if (estDansClasse && value is Map) {
              bool present = value["present"] == true;
              bool retard = value["retard"] == true;
              
              debugPrint("   → Present: $present, Retard: $retard");

              if (retard) {
                nouveauxStatuts[etuId] = "retard";
              } else if (present) {
                nouveauxStatuts[etuId] = "present";
              }
              }
            });
          }
        } else {
        debugPrint("📭 Pas de données de pointage pour aujourd'hui");
      }

      debugPrint("✅ Mise à jour statuts: $nouveauxStatuts");
      
          setState(() {
        statutEtudiants = nouveauxStatuts;
      });
    }, onError: (error) {
      debugPrint("❌ Erreur Firebase: $error");
    });
  }
  
  @override
  void dispose() {
    _pointageSubscription?.cancel();
    super.dispose();
  }

  // Charger les informations de l'enseignant connecté
  Future<void> _chargerEnseignant() async {
    if (currentUser == null) return;
    
    try {
      final snap = await dbRef
          .child("enseignants")
          .orderByChild("uid")
          .equalTo(currentUser!.uid)
          .once();
      
      if (snap.snapshot.exists) {
        final data = snap.snapshot.value as Map;
        final key = data.keys.first;
        final enseignantData = data[key] as Map;
        
        setState(() {
          enseignantId = key.toString();
          enseignantNom = "${enseignantData["prenom"] ?? ""} ${enseignantData["nom"] ?? ""}".trim();
        });
        
        debugPrint("👨‍🏫 Enseignant: $enseignantId - $enseignantNom");
      }
    } catch (e) {
      debugPrint("❌ Erreur chargement enseignant: $e");
    }
  }

  // =====================================================
  // 📧 CONFIGURATION EMAILJS - Mettez vos vrais IDs ici
  // =====================================================
  // Trouvez ces IDs sur https://dashboard.emailjs.com/
  static const String _emailJsServiceId = "service_etudiant";   // Email Services → votre service
  static const String _emailJsTemplateId = "template_efwoxjc"; // Email Templates → votre template  
  static const String _emailJsPublicKey = "PnCuvDW0kQBr0U4Kp";   // Account → API Keys

  // Envoyer un email via EmailJS
  Future<bool> _envoyerEmailParent({
    required String emailParent,
    required String nomEtudiant,
    required String prenomEtudiant,
    required String nomClasse,
    required String date,
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
            "class_name": nomClasse,
            "date": date,
            "message": "Nous vous informons que votre enfant $prenomEtudiant $nomEtudiant "
                "de la classe $nomClasse était absent(e) le $date.",
          },
        }),
      );

      debugPrint("📧 Email à $emailParent: ${response.statusCode}");
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Erreur email: $e");
      return false;
    }
  }

  // =====================================================
  // 📋 SAUVEGARDER LE RAPPORT POUR L'ADMINISTRATION
  // =====================================================
  Future<void> _sauvegarderRapport(int emailsEnvoyes, int emailsEchoues) async {
    // S'assurer que l'enseignant est chargé
    if (enseignantId == null && currentUser != null) {
      await _chargerEnseignant();
    }
    
    // Utiliser "inconnu" si toujours null
    final String ensId = enseignantId ?? "inconnu";
    final String ensNom = enseignantNom ?? "Enseignant";
    
    debugPrint("📋 Sauvegarde rapport - Enseignant: $ensId ($ensNom)");
    
    // Compter les statuts
    int presents = 0;
    int retards = 0;
    int absents = 0;
    
    Map<String, dynamic> detailsRapport = {};
    
    for (var etu in widget.etudiants) {
      String etuId = etu["id"].toString();
      String statut = statutEtudiants[etuId] ?? "absent";
      
      if (statut == "present") presents++;
      else if (statut == "retard") retards++;
      else absents++;
      
      detailsRapport[etuId] = {
        "nom": etu["nom"] ?? "",
        "prenom": etu["prenom"] ?? "",
        "present": statut == "present" || statut == "retard",
        "retard": statut == "retard",
      };
    }

    // Données du rapport
    final rapportData = {
      "classe": widget.nomClasse,
      "classe_id": widget.classeId,
      "enseignant_id": ensId,
      "enseignant_nom": ensNom,
      "timestamp": DateTime.now().toIso8601String(),
      "total_etudiants": widget.etudiants.length,
      "presents": presents,
      "retards": retards,
      "absents": absents,
      "emails_envoyes": emailsEnvoyes,
      "details": detailsRapport,
    };

    try {
      // ✅ TOUJOURS sauvegarder le rapport PAR ENSEIGNANT ET PAR CLASSE
      // Structure: rapports/$date/$enseignantId/$classeId
      await dbRef.child("rapports/$aujourdHui/$ensId/${widget.classeId}").set(rapportData);
      debugPrint("✅ Rapport sauvegardé: rapports/$aujourdHui/$ensId/${widget.classeId}");

      // Sauvegarder la validation
      await dbRef.child("validations/$aujourdHui/${widget.classeId}/$ensId").set({
        "timestamp": DateTime.now().toIso8601String(),
        "classe": widget.nomClasse,
        "enseignant_id": ensId,
        "enseignant_nom": ensNom,
        "absents": absents,
        "emails_envoyes": emailsEnvoyes,
        "emails_echoues": emailsEchoues,
      });

      debugPrint("✅ Validation sauvegardée pour ${widget.classeId} par $ensId");
    } catch (e) {
      debugPrint("❌ Erreur sauvegarde rapport: $e");
      rethrow;
    }
  }

  // =====================================================
  // 📧 VALIDER ET ENVOYER LES EMAILS AUX PARENTS DES ABSENTS
  // =====================================================
  Future<void> _validerEtEnvoyerEmails() async {
    // 1️⃣ Récupérer la liste des étudiants absents
    List<Map<String, dynamic>> etudiantsAbsents = [];
    
    for (var etu in widget.etudiants) {
      String etuId = etu["id"].toString();
      String statut = statutEtudiants[etuId] ?? "absent";
      if (statut == "absent") {
        final snapshot = await dbRef.child("etudiants/$etuId").get();
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          etudiantsAbsents.add({
            "id": etuId,
            "nom": data["nom"] ?? "",
            "prenom": data["prenom"] ?? "",
            "email_parent": data["email_parent"] ?? "",
          });
        }
      }
    }

    // Si aucun absent → sauvegarder le rapport quand même et afficher message
    if (etudiantsAbsents.isEmpty) {
      await _sauvegarderRapport(0, 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Rapport validé ! Aucun absent aujourd'hui 🎉"), backgroundColor: Colors.green),
        );
      }
      return;
    }

    // 2️⃣ Filtrer ceux qui ont un email parent
    List<Map<String, dynamic>> etudiantsAvecEmail = etudiantsAbsents
        .where((e) => e["email_parent"] != null && e["email_parent"].toString().isNotEmpty)
        .toList();

    // 3️⃣ Confirmation
    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("📧 Notifier les parents"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${etudiantsAbsents.length} élève(s) absent(s) :", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...etudiantsAbsents.map((e) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 16, color: e["email_parent"].toString().isNotEmpty ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text("${e["prenom"]} ${e["nom"]}", style: const TextStyle(fontSize: 14))),
                    if (e["email_parent"].toString().isNotEmpty)
                      const Icon(Icons.email, size: 14, color: Colors.green),
                  ],
                ),
              )),
              const Divider(),
              Text("${etudiantsAvecEmail.length} email(s) seront envoyés automatiquement", style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, color: Colors.white, size: 18),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB721D)),
            onPressed: () => Navigator.pop(context, true),
            label: const Text("Envoyer", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmation != true) return;

    // 4️⃣ Afficher le loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Envoi des emails en cours..."),
          ],
        ),
      ),
    );

    int emailsEnvoyes = 0;
    int emailsEchoues = 0;

    try {
      // 5️⃣ Envoyer les emails automatiquement
      for (var etu in etudiantsAvecEmail) {
        bool success = await _envoyerEmailParent(
          emailParent: etu["email_parent"],
          nomEtudiant: etu["nom"],
          prenomEtudiant: etu["prenom"],
          nomClasse: widget.nomClasse,
          date: aujourdHui,
        );

        if (success) {
          emailsEnvoyes++;
        } else {
          emailsEchoues++;
        }

        // Enregistrer dans Firebase
        await dbRef.child("notifications/$aujourdHui/${widget.classeId}/${etu["id"]}").set({
          "email_parent": etu["email_parent"],
          "nom": etu["nom"],
          "prenom": etu["prenom"],
          "envoye": success,
          "timestamp": DateTime.now().toIso8601String(),
        });
      }

      // 6️⃣ Sauvegarder le rapport complet
      await _sauvegarderRapport(emailsEnvoyes, emailsEchoues);

      // Fermer le loader
      if (mounted) Navigator.pop(context);

      // 7️⃣ Afficher le résultat
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                Icon(emailsEnvoyes > 0 ? Icons.check_circle : Icons.error, 
                     color: emailsEnvoyes > 0 ? Colors.green : Colors.red),
                const SizedBox(width: 10),
                const Text("Résultat"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("✅ Emails envoyés : $emailsEnvoyes"),
                Text("❌ Échecs : $emailsEchoues"),
                if (emailsEchoues > 0) ...[
                  const SizedBox(height: 10),
                  const Text("Vérifiez votre configuration EmailJS", style: TextStyle(color: Colors.orange, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _changerStatut(String etuId, String nouveauStatut) async {
    setState(() {
      statutEtudiants[etuId] = nouveauStatut;
    });

    Map<String, dynamic> data = {
      "present": nouveauStatut == "present",
      "retard": nouveauStatut == "retard",
      "manuelle": true,
      "heure": DateTime.now().toIso8601String(),
    };

    await dbRef.child("pointages/$aujourdHui/${widget.classeId}/$etuId").set(data);
  }

  Color _getColor(String statut) {
    switch (statut) {
      case "present":
        return Colors.green;
      case "retard":
        return Color(0xFFFB721D);
      case "absent":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getIcon(String statut) {
    switch (statut) {
      case "present":
        return Icons.check_circle;
      case "retard":
        return Icons.access_time;
      case "absent":
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    int total = widget.etudiants.length;

    int presents = statutEtudiants.values.where((s) => s == "present").length;
    int retards = statutEtudiants.values.where((s) => s == "retard").length;
    int absents = statutEtudiants.values.where((s) => s == "absent").length;

    return Scaffold(
      appBar: AppBar(
        title: Text("Détails - ${widget.nomClasse}"),
        backgroundColor: Color(0xFFFB721D),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),

      body: Column(
        children: [
          // ---------------------
          // CARTE DE RÉSUMÉ
          // ---------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFFB721D),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  "Statistiques du jour",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBox("Présents", presents, Colors.green),
                    _statBox("Retards", retards, Color(0xFFFB721D)),
                    _statBox("Absents", absents, Colors.red),
                  ],
                )
              ],
            ),
          ),

          // LISTE DES ÉTUDIANTS
          Expanded(
            child: widget.etudiants.isEmpty
                ? const Center(child: Text("Aucun étudiant dans cette classe"))
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.etudiants.length,
              itemBuilder: (ctx, i) {
                var etu = widget.etudiants[i];
                String etuId = etu["id"];
                String statut = statutEtudiants[etuId] ?? "absent";

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(
                      backgroundColor: _getColor(statut),
                      child: Icon(
                        _getIcon(statut),
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      "${etu["nom"]} ${etu["prenom"]}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    subtitle: Text("Empreinte ID : ${etu["empreinte_id"]}"),
                    trailing: Text(
                      statut == "present"
                          ? "Présent"
                          : statut == "retard"
                          ? "En retard"
                          : "Absent",
                      style: TextStyle(
                        color: _getColor(statut),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () => _openChangerStatut(context, etu, etuId),
                  ),
                );
              },
            ),
          ),

          // -------------------------------------------------------
          // BOUTON DE VALIDATION - Envoie les emails aux parents des absents
          // -------------------------------------------------------
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.email, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB721D),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _validerEtEnvoyerEmails,
                label: const Text(
                  "Valider et notifier les parents",
                  style: TextStyle(fontSize: 18, color: Colors.white),
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
        Text(
          "$value",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }

  void _openChangerStatut(BuildContext context, Map etu, String etuId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${etu["nom"]} ${etu["prenom"]}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _bottomButton(etuId, "present", Icons.check_circle, Colors.green, "Présent"),
            _bottomButton(etuId, "retard", Icons.access_time, Color(0xFFFB721D), "En retard"),
            _bottomButton(etuId, "absent", Icons.cancel, Colors.red, "Absent"),
          ],
        ),
      ),
    );
  }

  Widget _bottomButton(
      String etuId, String statut, IconData icon, Color color, String label) {
    return ListTile(
      leading: Icon(icon, color: color, size: 32),
      title: Text(label, style: const TextStyle(fontSize: 18)),
      onTap: () {
        _changerStatut(etuId, statut);
        Navigator.pop(context);
      },
    );
  }
}
