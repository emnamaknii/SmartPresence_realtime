import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/login_page.dart';
import 'screens/enseignant_page.dart';
import 'screens/enseignant_seances_page.dart'; // Nouvelle page séances
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'splash_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialiser les locales pour les dates en français
  await initializeDateFormatting('fr_FR', null);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Gestion Présence",
      debugShowCheckedModeBanner: false,

      // 🟧 Page qui s'ouvre au lancement
      home: SplashPage(),

      // 🟩 ROUTES IMPORTANTES
      routes: {
        '/login': (context) => LoginPage(),
        '/enseignant': (context) => const EnseignantSeancesPage(), // Utiliser la nouvelle page
        '/enseignant_old': (context) => const EnseignantPage(), // Garder l'ancienne si besoin
      },

    );
  }
}
