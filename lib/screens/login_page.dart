// lib/screens/login_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_page.dart';
import 'enseignant_seances_page.dart'; // Nouvelle page avec séances

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // Admin statique (ne passe PAS par Firebase Auth)
  static const String adminEmail = "admin";
  static const String adminPassword = "1234";

  Future<void> _seConnecter() async {
    String email = _emailController.text.trim().toLowerCase();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Champs obligatoires"), backgroundColor: Color(0xFFFB721D)),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 1. Admin statique (sans Firebase Auth)
    if (email == adminEmail && password == adminPassword) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminPage()),
      );
      return;
    }

    // 2. Enseignant → Firebase Auth
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Connexion réussie → EnseignantSeancesPage (avec gestion des séances)
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EnseignantSeancesPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String erreur = "Identifiants incorrects";
      
      // Codes d'erreur Firebase Auth (versions récentes)
      switch (e.code) {
        case 'user-not-found':
          erreur = "Aucun compte avec cet email";
          break;
        case 'wrong-password':
          erreur = "Mot de passe incorrect";
          break;
        case 'invalid-credential':
          erreur = "Email ou mot de passe incorrect";
          break;
        case 'invalid-email':
          erreur = "Format d'email invalide";
          break;
        case 'user-disabled':
          erreur = "Ce compte a été désactivé";
          break;
        case 'too-many-requests':
          erreur = "Trop de tentatives, réessayez plus tard";
          break;
        case 'network-request-failed':
          erreur = "Erreur réseau, vérifiez votre connexion";
          break;
        default:
          erreur = "Erreur: ${e.code}";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(erreur), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      // Debug: afficher l'erreur exacte
      debugPrint("Erreur de connexion: $e");
      debugPrint("Type d'erreur: ${e.runtimeType}");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              const Icon(Icons.check_circle, size: 100, color: Color(0xFFFB721D)),
              const SizedBox(height: 20),
              const Text("SmartPresence", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 60),

              // Card de connexion
              Card(
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      // Champ Email / Username
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email",
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFB721D), width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Champ Mot de passe
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "Mot de passe",
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFB721D), width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Bouton Connexion
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _seConnecter,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFB721D),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 8,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text("Se connecter", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),


            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}