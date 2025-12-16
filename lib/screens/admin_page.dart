import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'ajouter_etudiant.dart';
import 'ajouter_enseignant_page.dart';
import 'ajouter_classe_page.dart';
import 'admin_rapports_page.dart';
import 'admin_billets_page.dart';
import 'login_page.dart';

class AdminPage extends StatefulWidget {
  AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();

  int totalEtudiants = 0;
  int totalEnseignants = 0;
  int totalClasses = 0;
  
  // Stocker les abonnements pour les annuler dans dispose()
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _ecouterStatistiques();
  }
  
  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _ecouterStatistiques() {
    // Écouter les étudiants en temps réel
    final etudiantsSub = dbRef.child("etudiants").onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value != null) {
        setState(() => totalEtudiants = (event.snapshot.value as Map).length);
      } else {
        setState(() => totalEtudiants = 0);
      }
    });
    _subscriptions.add(etudiantsSub);

    // Écouter les enseignants en temps réel
    final enseignantsSub = dbRef.child("enseignants").onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value != null) {
        setState(() => totalEnseignants = (event.snapshot.value as Map).length);
      } else {
        setState(() => totalEnseignants = 0);
      }
    });
    _subscriptions.add(enseignantsSub);

    // Écouter les classes en temps réel
    final classesSub = dbRef.child("classes").onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value != null) {
        setState(() => totalClasses = (event.snapshot.value as Map).length);
      } else {
        setState(() => totalClasses = 0);
      }
    });
    _subscriptions.add(classesSub);
  }

  void _deconnexion(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout, color: Color(0xFFFB721D), size: 40),
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment quitter ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFB721D)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Se déconnecter", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LoginPage()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("Tableau de bord Admin",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: const Color(0xFFFB721D),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Déconnexion",
            onPressed: () => _deconnexion(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // --------------------------
            //  BLOC STATISTIQUES
            // --------------------------
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFB721D),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statBox("Étudiants", totalEtudiants, Colors.green),
                  _statBox("Enseignants", totalEnseignants, Colors.blueAccent),
                  _statBox("Classes", totalClasses, Colors.orangeAccent),
                ],
              ),
            ),

            // Carte de bienvenue
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                      colors: [const Color(0xFFFB721D), const Color(0xFFFB721D).withOpacity(0.85)]),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.admin_panel_settings, size: 50, color: Colors.white),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Bienvenue Administrateur",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text("Gérez votre établissement",
                              style: TextStyle(fontSize: 14, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // 3 BOUTONS PLUS PETITS & PLUS COMPACT
            Expanded(
              child: GridView.count(
                crossAxisCount: 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 7.0,
                children: [
                  _buildCompactButton(
                    context: context,
                    icon: Icons.person_add,
                    title: "Étudiants",
                    color: const Color(0xFFFB721D),
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AjouterEtudiant())),
                  ),
                  _buildCompactButton(
                    context: context,
                    icon: Icons.school,
                    title: "Enseignants",
                    color: const Color(0xFFFB721D),
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AjouterEnseignantPage())),
                  ),
                  _buildCompactButton(
                    context: context,
                    icon: Icons.class_,
                    title: "Classes",
                    color: const Color(0xFFFB721D),
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AjouterClassePage())),
                  ),
                  _buildCompactButton(
                    context: context,
                    icon: Icons.picture_as_pdf,
                    title: "Rapports",
                    color: const Color(0xFFFB721D),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminRapportsPage()),
                    ),
                  ),
                  _buildCompactButton(
                    context: context,
                    icon: Icons.confirmation_number,
                    title: "Billets de Présence",
                    color: Color(0xFFFB721D),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminBilletsPage()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          "$value",
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildCompactButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withOpacity(0.25),
                child: Icon(icon, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 22, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
