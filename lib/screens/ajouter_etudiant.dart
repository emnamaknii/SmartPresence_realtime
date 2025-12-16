import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/seance_config.dart';

class AjouterEtudiant extends StatefulWidget {
  const AjouterEtudiant({super.key});
  @override
  State<AjouterEtudiant> createState() => _AjouterEtudiantState();
}

class _AjouterEtudiantState extends State<AjouterEtudiant> {
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _emailController = TextEditingController();

  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  late final DatabaseReference etudiantsRef = dbRef.child("etudiants");
  late final DatabaseReference classesRef = dbRef.child("classes");

  int? empreinteID;
  bool isEnregistering = false;
  String? classeSelectionnee;

  List<Map<String, dynamic>> classesList = [];
  Map<String, dynamic> etudiantsMap = {};

  // Abonnements Firebase à annuler dans dispose()
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    chargerClasses();
    ecouterEtudiants();
  }

  void chargerClasses() {
    final sub = classesRef.onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists) return;
      Map data = event.snapshot.value as Map;
      List<Map<String, dynamic>> temp = [];
      data.forEach((key, value) {
        temp.add({"id": key, "nom": value["nom"] ?? "Classe sans nom"});
      });
      temp.sort((a, b) => a["nom"].compareTo(b["nom"]));
      setState(() {
        classesList = temp;
        if (classeSelectionnee == null && classesList.isNotEmpty) {
          classeSelectionnee = classesList.first["id"];
        }
      });
    });
    _subscriptions.add(sub);
  }

  void ecouterEtudiants() {
    final sub = etudiantsRef.onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() => etudiantsMap = {});
        return;
      }
      setState(() {
        etudiantsMap = Map<String, dynamic>.from(event.snapshot.value as Map);
      });
    });
    _subscriptions.add(sub);
  }

  Future<bool> testConnexionESP32() async {
    try {
      var response = await http
          .get(Uri.parse("http://172.20.10.6/"))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      print("Test connexion échoué: $e");
      return false;
    }
  }

  Future<void> enregistrerEmpreinte() async {
    if (isEnregistering) return;

    // Test de connexion d'abord
    if (!await testConnexionESP32()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ESP32 non connecté. Vérifiez l'IP et le réseau WiFi!")),
        );
      }
      return;
    }

    if (mounted) setState(() => isEnregistering = true);

    try {
      print("1. Passage en mode enregistrement...");
      // Étape 1: Passer l'ESP32 en mode enregistrement
      var modeResponse = await http
          .get(Uri.parse("http://172.20.10.6/mode?m=enregistrement"))
          .timeout(const Duration(seconds: 3));

      if (modeResponse.statusCode != 200) {
        throw Exception("Erreur changement de mode");
      }

      print("2. Mode enregistrement activé, démarrage de l'enregistrement...");
      // Petite pause pour laisser l'ESP32 changer de mode
      await Future.delayed(const Duration(milliseconds: 500));

      // Étape 2: Démarrer l'enregistrement
      var response = await http
          .get(Uri.parse("http://172.20.10.6/enregistrer"))
          .timeout(const Duration(seconds: 5));

      print("3. Réponse ESP32: ${response.body}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        String body = response.body.trim();

        if (body == "DEJA_EN_COURS") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Un enregistrement est déjà en cours")),
          );
        } else {
          int? id = int.tryParse(body);
          if (id != null && id > 0) {
            setState(() => empreinteID = id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Placez votre doigt sur le capteur! ID: $id")),
            );

            // Attendre le résultat final
            await attendreResultatEnregistrement();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Réponse invalide de l'ESP32")),
            );
          }
        }
      } else {
        throw Exception("Code HTTP: ${response.statusCode}");
      }
    } catch (e) {
      print("Erreur enregistrement: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => isEnregistering = false);
    }
  }

  Future<void> attendreResultatEnregistrement() async {
    print("4. Attente du résultat...");
    for (int i = 0; i < 30; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));
      try {
        var res = await http.get(Uri.parse("http://172.20.10.6/resultat"));
        String result = res.body.trim();
        print("Résultat check $i: $result");

        if (!mounted) return;

        if (result == "SUCCES" || result == "ENREGISTREMENT_REUSSI") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Empreinte enregistrée avec succès !"),
              backgroundColor: Color(0xFFFB721D),
            ),
          );
          return;
        } else if (result == "ERREUR" || result == "ECHEC" || result == "TIMEOUT") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Échec de l'enregistrement de l'empreinte")),
          );
          setState(() => empreinteID = null);
          return;
        } else if (int.tryParse(result) != null) {
          // Si on reçoit un nombre, c'est l'ID final
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Empreinte enregistrée! ID: $result"),
              backgroundColor: Color(0xFFFB721D),
            ),
          );
          return;
        }
      } catch (_) {
        print("Erreur lors de la vérification du résultat");
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Timeout - Vérifiez le capteur")),
      );
      setState(() => empreinteID = null);
    }
  }

  Future<void> ajouterEtudiant() async {
    if (empreinteID == null || classeSelectionnee == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Empreinte et classe obligatoires !")),
        );
      }
      return;
    }

    String etuId = "ETU${empreinteID.toString().padLeft(3, '0')}";
    String today = DateTime.now().toIso8601String().split("T")[0]; // Format YYYY-MM-DD

    try {
      // 1. Ajouter l'étudiant dans /etudiants/
      await etudiantsRef.child(etuId).set({
        "nom": _nomController.text.trim(),
        "prenom": _prenomController.text.trim(),
        "email_parent": _emailController.text.trim(),
        "empreinte_id": empreinteID,
        "classe": classeSelectionnee,
        "date_inscription": DateTime.now().toIso8601String(),
      });

      // 2. Ajouter dans la classe
      await classesRef
          .child("$classeSelectionnee/etudiants/$etuId")
          .set(true);

      // 3. INITIALISER LE POINTAGE À "ABSENT" POUR AUJOURD'HUI
      await dbRef.child("pointages/$today/$classeSelectionnee/$etuId").set({
        "present": false,
        "retard": false,
        "manuelle": false,
        "heure": null,
      });

      // 4. DONNER UN BILLET AUTOMATIQUE POUR LA SÉANCE ACTUELLE
      // Cela permet au nouvel étudiant de pointer sans être bloqué par les séances passées
      final seanceActuelle = SeanceConfig.getSeanceActuelle();
      if (seanceActuelle != null) {
        String seanceId = seanceActuelle["id"].toString();
        
        // Donner un billet pour cette séance
        await dbRef.child("billets_presence/$today/$etuId/$seanceId").set(true);
        
        // Marquer comme "nouveau" dans les séances passées pour ne pas être pénalisé
        // L'étudiant est considéré comme "inscrit aujourd'hui" donc pas de vérification des absences passées
        await dbRef.child("etudiants_nouveaux/$today/$etuId").set({
          "heure_inscription": DateTime.now().toIso8601String(),
          "classe": classeSelectionnee,
          "seance_inscription": seanceId,
        });
        
        debugPrint("✅ Billet automatique donné pour $etuId - Séance $seanceId");
      }

      if (mounted) {
        String message = "Étudiant $etuId ajouté";
        if (seanceActuelle != null) {
          message += " + billet pour ${seanceActuelle["id"]}";
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Color(0xFFFB721D),
          ),
        );

        // Reset
        _nomController.clear();
        _prenomController.clear();
        _emailController.clear();
        setState(() => empreinteID = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e")),
        );
      }
    }
  }

  // Fonction pour modifier la classe d'un étudiant
  Future<void> _modifierClasse(String etuId, Map etu, String ancienneClasseId) async {
    if (!mounted || classesList.isEmpty) return;
    
    String? nouvelleClasse = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Changer la classe de ${etu["prenom"]} ${etu["nom"]}"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: classesList.length,
            itemBuilder: (_, i) {
              var classe = classesList[i];
              bool isSelected = classe["id"] == ancienneClasseId;
              return ListTile(
                title: Text(classe["nom"]),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFFB721D)) : null,
                tileColor: isSelected ? Colors.orange.withOpacity(0.1) : null,
                onTap: () => Navigator.pop(ctx, classe["id"]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text("Annuler"),
          ),
        ],
      ),
    );

    if (nouvelleClasse == null || nouvelleClasse == ancienneClasseId || !mounted) return;

    try {
      // 1. Mettre à jour la classe de l'étudiant
      await etudiantsRef.child(etuId).update({"classe": nouvelleClasse});

      // 2. Retirer de l'ancienne classe
      if (ancienneClasseId.isNotEmpty) {
        await classesRef.child("$ancienneClasseId/etudiants/$etuId").remove();
      }

      // 3. Ajouter à la nouvelle classe
      await classesRef.child("$nouvelleClasse/etudiants/$etuId").set(true);

      if (mounted) {
        String nouvelleClasseNom = classesList.firstWhere(
          (c) => c["id"] == nouvelleClasse,
          orElse: () => {"nom": "Nouvelle classe"},
        )["nom"];
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${etu["prenom"]} transféré vers $nouvelleClasseNom"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> supprimerEtudiant(String etuId, String classeId) async {
    if (!mounted) return;
    
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer"),
        content: Text("Supprimer $etuId ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Supprimer", style: TextStyle(color: Color(0xFFFB721D)))),
        ],
      ),
    ) ??
        false;

    if (!confirm || !mounted) return;

    try {
      await etudiantsRef.child(etuId).remove();
      await classesRef.child("$classeId/etudiants/$etuId").remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Étudiant supprimé")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin - Gestion Étudiants"),
        backgroundColor: Color(0xFFFB721D),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // === FORMULAIRE AJOUT ===
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                        "Nouvel étudiant",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _nomController,
                        decoration: const InputDecoration(
                            labelText: "Nom*",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person)
                        )
                    ),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _prenomController,
                        decoration: const InputDecoration(
                            labelText: "Prénom*",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline)
                        )
                    ),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                            labelText: "Email De Parent",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email)
                        ),
                        keyboardType: TextInputType.emailAddress
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: classeSelectionnee,
                      decoration: const InputDecoration(
                          labelText: "Classe*",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.class_)
                      ),
                      items: classesList.map((c) {
                        return DropdownMenuItem<String>(
                          value: c["id"] as String,
                          child: Text(c["nom"] as String? ?? "Classe sans nom"),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => classeSelectionnee = v),
                    ),
                    const SizedBox(height: 20),
                    // Bouton d'enregistrement d'empreinte
                    ElevatedButton.icon(
                      onPressed: isEnregistering ? null : enregistrerEmpreinte,
                      icon: isEnregistering
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white
                        ),
                      )
                          : const Icon(Icons.fingerprint),
                      label: Text(
                          isEnregistering
                              ? "Enregistrement en cours..."
                              : "1. Enregistrer l'empreinte"
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFB721D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Affichage de l'ID d'empreinte
                    if (empreinteID != null)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Color(0xFFFB721D),
                            border: Border.all(color: Colors.green),
                            borderRadius: BorderRadius.circular(8)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Color(0xFFFB721D)),
                            SizedBox(width: 10),
                            Text(
                              "Empreinte prête! ID: $empreinteID",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:Color(0xFFFB721D)
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Bouton d'ajout d'étudiant
                    ElevatedButton.icon(
                      onPressed: empreinteID == null ? null : ajouterEtudiant,
                      icon: const Icon(Icons.add),
                      label: const Text("2. Ajouter l'étudiant à la classe"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: empreinteID == null ? Colors.grey : Color(0xFFFB721D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (empreinteID != null)
                      Text(
                        "Remplissez les informations ci-dessus puis cliquez ici",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            // === LISTE DES ÉTUDIANTS ===
            Text(
                "Étudiants enregistrés (${etudiantsMap.length})",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 10),
            etudiantsMap.isEmpty
                ? const Card(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        "Aucun étudiant enregistré",
                        textAlign: TextAlign.center
                    )
                )
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: etudiantsMap.length,
              itemBuilder: (ctx, i) {
                String key = etudiantsMap.keys.elementAt(i);
                var etu = etudiantsMap[key];
                if (etu == null) return const SizedBox.shrink();
                
                String classeId = etu["classe"]?.toString() ?? "";
                String classeNom = "Classe inconnue";
                
                // Trouver le nom de la classe de manière sécurisée
                if (classeId.isNotEmpty && classesList.isNotEmpty) {
                  try {
                    var found = classesList.where((c) => c["id"] == classeId);
                    if (found.isNotEmpty) {
                      classeNom = found.first["nom"]?.toString() ?? "Classe inconnue";
                    }
                  } catch (_) {}
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _modifierClasse(key, etu, classeId),
                    leading: CircleAvatar(
                        backgroundColor: Color(0xFFFB721D),
                        child: Text(
                          (etu["nom"] != null && etu["nom"].toString().isNotEmpty) 
                              ? etu["nom"].toString()[0].toUpperCase() 
                              : "?"
                        )
                    ),
                    title: Text(
                        "${etu["nom"] ?? ''} ${etu["prenom"] ?? ''}".trim(),
                        style: const TextStyle(fontWeight: FontWeight.bold)
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.class_, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text("$classeNom", style: const TextStyle(color: Color(0xFFFB721D))),
                            const Text(" (tap pour changer)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        Text("ID Empreinte: ${etu["empreinte_id"] ?? '?'}"),
                        if (etu["email_parent"] != null && etu["email_parent"].toString().isNotEmpty)
                          Text("Email parent: ${etu["email_parent"]}"),
                      ],
                    ),
                    trailing: IconButton(
                        icon: const Icon(Icons.delete, color:Color(0xFFFB721D)),
                        onPressed: () => supprimerEtudiant(key, classeId)
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Annuler tous les abonnements Firebase
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _nomController.dispose();
    _prenomController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}