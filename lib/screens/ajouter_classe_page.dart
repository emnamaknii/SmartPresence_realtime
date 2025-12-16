// lib/screens/ajouter_classe_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AjouterClassePage extends StatefulWidget {
  const AjouterClassePage({super.key});

  @override
  State<AjouterClassePage> createState() => _AjouterClassePageState();
}

class _AjouterClassePageState extends State<AjouterClassePage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();

  // Liste de tous les enseignants
  List<Map<String, dynamic>> enseignantsList = [];
  // Liste des enseignants sélectionnés (IDs)
  List<String> enseignantsSelectionnes = [];

  bool isLoading = false;
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  
  // Abonnement Firebase à annuler
  StreamSubscription? _enseignantsSubscription;

  @override
  void initState() {
    super.initState();
    chargerEnseignants();
  }

  void chargerEnseignants() {
    _enseignantsSubscription = dbRef.child("enseignants").onValue.listen((event) {
      if (!mounted) return;
      
      if (!event.snapshot.exists) {
        setState(() => enseignantsList = []);
        return;
      }

      Map data = event.snapshot.value as Map;
      List<Map<String, dynamic>> temp = [];

      data.forEach((key, value) {
        temp.add({
          "id": key,
          "nom": value["nom"] ?? "",
          "prenom": value["prenom"] ?? "",
          "email": value["email"] ?? "",
        });
      });

      temp.sort((a, b) =>
          ("${a["nom"]} ${a["prenom"]}".trim())
              .compareTo("${b["nom"]} ${b["prenom"]}".trim()));

      if (mounted) {
        setState(() => enseignantsList = temp);
      }
    });
  }

  Future<void> _creerClasse() async {
    if (!_formKey.currentState!.validate()) return;
    if (enseignantsSelectionnes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Veuillez sélectionner au moins un enseignant"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      String nomClasse = _nomController.text.trim().toUpperCase();

      // Générer l'ID classe : CLS001, CLS002...
      DatabaseEvent snapshot = await dbRef.child("classes").orderByKey().once();
      int prochainNumero = 1;

      if (snapshot.snapshot.value != null) {
        Map data = snapshot.snapshot.value as Map;
        List<String> keys = data.keys.cast<String>().toList()
          ..sort();
        if (keys.isNotEmpty && keys.last.startsWith("CLS")) {
          prochainNumero = int.parse(keys.last.substring(3)) + 1;
        }
      }

      String classeId = "CLS${prochainNumero.toString().padLeft(3, '0')}";

      // Créer la classe avec la liste des enseignants
      Map<String, dynamic> classeData = {
        "id": classeId,
        "nom": nomClasse,
        "date_creation": DateTime.now().toIso8601String(),
        "etudiants": <String, bool>{},
        "enseignants": <String, bool>{},
      };

      for (String ensId in enseignantsSelectionnes) {
        classeData["enseignants"][ensId] = true;
      }

      await dbRef.child("classes/$classeId").set(classeData);

      // Mettre à jour chaque enseignant sélectionné (relation bidirectionnelle)
      for (String ensId in enseignantsSelectionnes) {
        await dbRef.child("enseignants/$ensId/classes/$classeId").set(true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Classe $classeId créée avec succès !"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Reset
        _nomController.clear();
        setState(() => enseignantsSelectionnes.clear());
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("Créer une Classe", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Card(
            elevation: 14,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFFFB721D).withOpacity(0.15),
                    child: const Icon(Icons.class_rounded, size: 60, color: Color(0xFFFB721D)),
                  ),
                  const SizedBox(height: 20),
                  const Text("Nouvelle Classe", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),

                  // Nom de la classe
                  TextFormField(
                    controller: _nomController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDecoration("Nom de la classe *", Icons.school_rounded, hint: "Ex: 7ème année"),
                    validator: (v) => v!.trim().isEmpty ? "Nom obligatoire" : null,
                  ),
                  const SizedBox(height: 25),

                  // Sélection multiple des enseignants
                  InputDecorator(
                    decoration: _inputDecoration("Enseignants responsables *", Icons.people),
                    child: Column(
                      children: [
                        if (enseignantsList.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text("Aucun enseignant disponible"),
                          )
                        else
                          SizedBox(
                            height: 300,
                            child: SingleChildScrollView(
                              child: Column(
                                children: enseignantsList.map((ens) {
                                  String id = ens["id"];
                                  return CheckboxListTile(
                                    title: Text("${ens["nom"]} ${ens["prenom"]}".trim()),
                                    subtitle: Text(ens["email"], style: const TextStyle(fontSize: 12)),
                                    value: enseignantsSelectionnes.contains(id),
                                    onChanged: (bool? selected) {
                                      setState(() {
                                        if (selected == true) {
                                          enseignantsSelectionnes.add(id);
                                        } else {
                                          enseignantsSelectionnes.remove(id);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        const Divider(),
                        Text("${enseignantsSelectionnes.length} enseignant(s) sélectionné(s)",
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Bouton Créer
                  SizedBox(
                    width: double.infinity,
                    height: 62,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : _creerClasse,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFB721D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                        elevation: 12,
                      ),
                      icon: isLoading
                          ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : const Icon(Icons.add_circle_outline, size: 30),
                      label: Text(
                        isLoading ? "Création..." : "CRÉER LA CLASSE",
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFFFB721D)),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFFB721D), width: 2.5),
      ),
    );
  }

  @override
  void dispose() {
    _enseignantsSubscription?.cancel();
    _nomController.dispose();
    super.dispose();
  }
}