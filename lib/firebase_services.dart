import 'package:firebase_database/firebase_database.dart';

Future<void> pointageEtudiant(int empreinteId) async {
  final dbRef = FirebaseDatabase.instance.ref();

  // Chercher l'étudiant par empreinte_id
  final snapshot =
  await dbRef.child("etudiants").orderByChild("empreinte_id").equalTo(empreinteId).get();

  if (snapshot.exists) {
    final etuId = snapshot.children.first.key!;
    final classeId = snapshot.children.first.child("classe").value;

    String today = DateTime.now().toIso8601String().split("T")[0];

    // Marquer la présence
    await dbRef.child("presences/$classeId/$etuId/$today").set({
      "present": true,
    });

    print("Étudiant $etuId marqué présent !");
  } else {
    print("Empreinte non reconnue");
  }
}
