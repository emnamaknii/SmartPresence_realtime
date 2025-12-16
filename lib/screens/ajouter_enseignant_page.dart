// lib/screens/ajouter_enseignant_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'admin_page.dart';
import 'package:firebase_auth/firebase_auth.dart';


class AjouterEnseignantPage extends StatefulWidget {
  const AjouterEnseignantPage({super.key});

  @override
  State<AjouterEnseignantPage> createState() => _AjouterEnseignantPageState();
}

class _AjouterEnseignantPageState extends State<AjouterEnseignantPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool isLoading = false;
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();



  Future<void> _ajouterEnseignant() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      String email = _emailController.text.trim().toLowerCase();
      String password = _passwordController.text.trim();

      // 1️⃣ Création du compte Firebase Auth
      final auth = FirebaseAuth.instance;
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      String uid = userCredential.user!.uid;

      // 2️⃣ Générer un ID style ENS001
      DatabaseReference enseignantsRef = dbRef.child("enseignants");
      DatabaseEvent event = await enseignantsRef.once();
      int count = event.snapshot.children.length;
      String newId = "ENS${(count + 1).toString().padLeft(3, '0')}";

      // 3️⃣ Enregistrement conforme au format officiel
      await enseignantsRef.child(newId).set({
        "id": newId,
        "uid": uid,
        "email": email,
        "nom": _nomController.text.trim().toUpperCase(),
        "prenom": _prenomController.text.trim(),
        "date_creation": DateTime.now().toIso8601String(),
        "classes": {},
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Enseignant ajouté avec succès ! ID : $newId"),
            backgroundColor: Color(0xFFFB721D),
          ),
        );

        _nomController.clear();
        _prenomController.clear();
        _emailController.clear();
        _passwordController.clear();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur : $e"),
            backgroundColor: Colors.red,
          ),
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
        title: const Text("Ajouter un Enseignant", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Color(0xFFFB721D),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Card(
            elevation: 12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  // Icône + Titre
                  const Icon(Icons.school_rounded, size: 80, color: Color(0xFFFB721D)),
                  const SizedBox(height: 16),
                  const Text(
                    "Nouvel Enseignant",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 32),

                  // Champs
                  TextFormField(
                    controller: _nomController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDecoration("Nom *", Icons.person),
                    validator: (v) => v!.trim().isEmpty ? "Nom obligatoire" : null,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _prenomController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration("Prénom *", Icons.person_outline),
                    validator: (v) => v!.trim().isEmpty ? "Prénom obligatoire" : null,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDecoration("Email *", Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Email obligatoire";
                      if (!v.contains("@")) return "Email invalide";
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: _inputDecoration("Mot de passe *", Icons.lock_outline),
                    validator: (v) => v!.length >= 6 ? null : "Minimum 6 caractères",
                  ),
                  const SizedBox(height: 40),

                  // Bouton Ajouter
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : _ajouterEnseignant,
                      icon: isLoading
                          ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                          : const Icon(Icons.person_add_alt_1, size: 28),
                      label: Text(
                        isLoading ? "Ajout en cours..." : "AJOUTER L'ENSEIGNANT",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFB721D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 12,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Info utile
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Color(0xFFFB721D)),
                    ),
                    child: const Text(
                      "Les classes seront assignées plus tard depuis le tableau de bord admin.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFFFB721D)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Color(0xFFFB721D)),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFB721D), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFB721D), width: 2),
      ),
    );
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}