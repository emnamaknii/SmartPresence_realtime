#include <WiFi.h>
#include <WebServer.h>
#include <Adafruit_Fingerprint.h>
#include <HardwareSerial.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ArduinoJson.h>
#include <time.h>
#include <ESP32Servo.h>

// === CONFIGURATION WIFI ===
const char* ssid = "iPhone";
const char* password = "emna2026";

// === URL FIREBASE ===
const char* firebaseHost = "miniprojet-38c25-default-rtdb.europe-west1.firebasedatabase.app";

// === COMPOSANTS ===
HardwareSerial fingerSerial(2);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fingerSerial);
LiquidCrystal_I2C lcd(0x27, 16, 2);
WebServer server(80);
Servo porte;

// === CONFIGURATION SÉANCES ===
struct Seance {
  const char* id;
  int debutHeure;
  int debutMinute;
  int finHeure;
  int finMinute;
  int retardHeure;
  int retardMinute;
};

// 8 séances par jour
Seance seances[] = {
  {"S1", 8, 0, 9, 0, 8, 10},
  {"S2", 9, 0, 10, 0, 9, 10},
  {"S3", 10, 0, 11, 0, 10, 10},
  {"S4", 11, 0, 12, 0, 11, 10},
  {"S5", 13, 0, 14, 0, 13, 10},
  {"S6", 14, 0, 15, 0, 14, 10},
  {"S7", 15, 0, 16, 0, 15, 10},
  {"S8", 16, 0, 17, 0, 16, 10}
};
const int NB_SEANCES = 8;

// === VARIABLES GLOBALES ===
bool enregistrementEnCours = false;
int idAEnregistrer = -1;
String retour = "EN_ATTENTE";
bool modePointageActif = true;

// Cache pour éviter les requêtes répétées
String dernierEtuId = "";
unsigned long dernierPointageTime = 0;
const unsigned long COOLDOWN_POINTAGE = 5000; // 5 secondes entre deux pointages du même élève

// Configuration dynamique de séance (modifiable par l'enseignant)
struct ConfigSeance {
  int debutHeure = -1;
  int debutMinute = -1;
  int retardHeure = -1;
  int retardMinute = -1;
  bool accepterRetardataires = true;
  bool configChargee = false;
};
ConfigSeance configActuelle;

// ================== FONCTIONS UTILITAIRES ==================

String getDate() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return "2025-12-01";
  char buf[11];
  sprintf(buf, "%04d-%02d-%02d", timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday);
  return String(buf);
}

String getTimestamp() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return "";
  char buf[30];
  sprintf(buf, "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
          timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
          timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
  return String(buf);
}

int getCurrentMinutes() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return -1;
  return timeinfo.tm_hour * 60 + timeinfo.tm_min;
}

// Retourne l'index de la séance actuelle (-1 si aucune)
int getSeanceActuelle() {
  int minutes = getCurrentMinutes();
  if (minutes < 0) return -1;
  
  for (int i = 0; i < NB_SEANCES; i++) {
    int debut = seances[i].debutHeure * 60 + seances[i].debutMinute;
    int fin = seances[i].finHeure * 60 + seances[i].finMinute;
    if (minutes >= debut && minutes < fin) {
      return i;
    }
  }
  return -1;
}

// Vérifie si on est dans la période d'entrée autorisée (avant retard limite)
// Utilise la config de l'enseignant si disponible
bool estDansPeriodeEntree(int seanceIdx, String classeId) {
  if (seanceIdx < 0) return false;
  
  int minutes = getCurrentMinutes();
  
  int debutH, debutM, retardH, retardM;
  
  // Utiliser la config de l'enseignant si disponible (et si classeId fourni)
  if (classeId.length() > 0 && configActuelle.configChargee && configActuelle.debutHeure >= 0) {
    debutH = configActuelle.debutHeure;
    debutM = configActuelle.debutMinute;
    Serial.print("📌 Utilise heure début config: ");
    Serial.print(debutH);
    Serial.print(":");
    Serial.println(debutM);
  } else {
    debutH = seances[seanceIdx].debutHeure;
    debutM = seances[seanceIdx].debutMinute;
  }
  
  if (classeId.length() > 0 && configActuelle.configChargee && configActuelle.retardHeure >= 0) {
    retardH = configActuelle.retardHeure;
    retardM = configActuelle.retardMinute;
    Serial.print("📌 Utilise retard limite config: ");
    Serial.print(retardH);
    Serial.print(":");
    Serial.println(retardM);
  } else {
    retardH = seances[seanceIdx].retardHeure;
    retardM = seances[seanceIdx].retardMinute;
  }
  
  int debut = debutH * 60 + debutM;
  int retard = retardH * 60 + retardM;
  
  Serial.print("⏱️ Temps actuel: ");
  Serial.print(minutes);
  Serial.print(" | Début: ");
  Serial.print(debut);
  Serial.print(" | Limite retard: ");
  Serial.println(retard);
  
  return (minutes >= debut && minutes <= retard);
}

// Vérifie si l'élève est en retard (après les 5 premières minutes du début configuré)
bool estEnRetard(int seanceIdx) {
  if (seanceIdx < 0) return true;
  
  int minutes = getCurrentMinutes();
  
  int debutH, debutM;
  
  // Utiliser la config de l'enseignant si disponible
  if (configActuelle.configChargee && configActuelle.debutHeure >= 0) {
    debutH = configActuelle.debutHeure;
    debutM = configActuelle.debutMinute;
  } else {
    debutH = seances[seanceIdx].debutHeure;
    debutM = seances[seanceIdx].debutMinute;
  }
  
  int debut = debutH * 60 + debutM;
  
  return (minutes > debut + 5);
}

String formatEtuId(int id) {
  String etuId = "ETU";
  if (id < 10) etuId += "00";
  else if (id < 100) etuId += "0";
  etuId += String(id);
  return etuId;
}

// ================== FONCTIONS FIREBASE ==================

// Récupère la classe d'un étudiant
String getClasseEtudiant(String etuId) {
  HTTPClient http;
  WiFiClientSecure client;
  client.setInsecure();
  
  String url = "https://" + String(firebaseHost) + "/etudiants/" + etuId + "/classe.json";
  http.begin(client, url);
  http.setTimeout(5000);
  
  int code = http.GET();
  if (code != 200) {
    http.end();
    return "";
  }
  
  String classe = http.getString();
  http.end();
  
  // Enlever les guillemets
  classe.replace("\"", "");
  return classe;
}

// Vérifie si l'étudiant a un billet pour cette séance
bool aBilletPresence(String etuId, String seanceId) {
  HTTPClient http;
  WiFiClientSecure client;
  client.setInsecure();
  
  String date = getDate();
  String url = "https://" + String(firebaseHost) + "/billets_presence/" + date + "/" + etuId + "/" + seanceId + ".json";
  
  http.begin(client, url);
  http.setTimeout(5000);
  
  int code = http.GET();
  if (code != 200) {
    http.end();
    return false;
  }
  
  String response = http.getString();
  http.end();
  
  return (response == "true");
}

// Vérifie si l'étudiant était absent à la séance précédente
bool etaitAbsentSeancePrecedente(String etuId, String classeId, int seanceActuelleIdx) {
  if (seanceActuelleIdx <= 0) return false; // Première séance, pas de vérification
  
  String seancePrecedente = seances[seanceActuelleIdx - 1].id;
  
  HTTPClient http;
  WiFiClientSecure client;
  client.setInsecure();
  
  String date = getDate();
  String url = "https://" + String(firebaseHost) + "/pointages_seances/" + date + "/" + classeId + "/" + seancePrecedente + "/" + etuId + "/present.json";
  
  http.begin(client, url);
  http.setTimeout(5000);
  
  int code = http.GET();
  if (code != 200) {
    http.end();
    return true; // Pas de données = absent
  }
  
  String response = http.getString();
  http.end();
  
  return (response != "true");
}

// Charge la configuration de séance depuis Firebase (modifiée par l'enseignant)
void chargerConfigSeance(String classeId, String seanceId) {
  HTTPClient http;
  WiFiClientSecure client;
  client.setInsecure();
  
  String date = getDate();
  String url = "https://" + String(firebaseHost) + "/config_seances/" + date + "/" + classeId + "/" + seanceId + ".json";
  
  Serial.print("📥 Chargement config: ");
  Serial.println(url);
  
  http.begin(client, url);
  http.setTimeout(5000);
  
  int code = http.GET();
  if (code != 200) {
    http.end();
    Serial.println("⚠️ Pas de config personnalisée, utilisation par défaut");
    configActuelle.configChargee = false;
    return;
  }
  
  String response = http.getString();
  http.end();
  
  if (response == "null" || response.length() < 5) {
    configActuelle.configChargee = false;
    return;
  }
  
  Serial.print("📄 Config reçue: ");
  Serial.println(response);
  
  // Parser le JSON
  DynamicJsonDocument doc(512);
  DeserializationError error = deserializeJson(doc, response);
  if (error) {
    Serial.println("❌ Erreur parsing config");
    configActuelle.configChargee = false;
    return;
  }
  
  // Lire heure_debut si modifiée
  if (doc.containsKey("heure_debut")) {
    String heureDebut = doc["heure_debut"].as<String>();
    int idx = heureDebut.indexOf(':');
    if (idx > 0) {
      configActuelle.debutHeure = heureDebut.substring(0, idx).toInt();
      configActuelle.debutMinute = heureDebut.substring(idx + 1).toInt();
      Serial.print("⏰ Heure début modifiée: ");
      Serial.println(heureDebut);
    }
  }
  
  // Lire retard_limite si modifié
  if (doc.containsKey("retard_limite")) {
    String retardLimite = doc["retard_limite"].as<String>();
    int idx = retardLimite.indexOf(':');
    if (idx > 0) {
      configActuelle.retardHeure = retardLimite.substring(0, idx).toInt();
      configActuelle.retardMinute = retardLimite.substring(idx + 1).toInt();
      Serial.print("⏰ Retard limite modifié: ");
      Serial.println(retardLimite);
    }
  }
  
  // Lire accepter_retardataires (contrôle de la porte)
  if (doc.containsKey("accepter_retardataires")) {
    configActuelle.accepterRetardataires = doc["accepter_retardataires"].as<bool>();
    Serial.print("🚪 Porte: ");
    Serial.println(configActuelle.accepterRetardataires ? "OUVERTE" : "FERMÉE");
  } else {
    configActuelle.accepterRetardataires = true; // Par défaut ouverte
  }
  
  configActuelle.configChargee = true;
}

// Vérifie si l'enseignant accepte encore les retardataires
bool enseignantAccepteRetardataires(String classeId, String seanceId) {
  // Charger la config si pas encore fait
  if (!configActuelle.configChargee) {
    chargerConfigSeance(classeId, seanceId);
  }
  return configActuelle.accepterRetardataires;
}

// Marque la présence dans Firebase
void marquerPresence(int id, bool enRetard) {
  String etuId = formatEtuId(id);
  String date = getDate();
  String timestamp = getTimestamp();
  
  // Récupérer la classe
  String classeId = getClasseEtudiant(etuId);
  if (classeId.isEmpty()) {
    Serial.println("Classe non trouvée pour " + etuId);
    return;
  }
  
  int seanceIdx = getSeanceActuelle();
  if (seanceIdx < 0) {
    Serial.println("Pas de séance en cours");
    return;
  }
  
  String seanceId = seances[seanceIdx].id;
  
  // Construire le payload
  String payload = "{";
  payload += "\"present\":true,";
  payload += "\"retard\":" + String(enRetard ? "true" : "false") + ",";
  payload += "\"manuelle\":false,";
  payload += "\"seance\":\"" + seanceId + "\",";
  payload += "\"heure\":\"" + timestamp + "\"";
  payload += "}";
  
  HTTPClient http;
  WiFiClientSecure client;
  client.setInsecure();
  
  // Sauvegarder dans pointages_seances (par séance)
  String urlSeance = "https://" + String(firebaseHost) + "/pointages_seances/" + date + "/" + classeId + "/" + seanceId + "/" + etuId + ".json";
  http.begin(client, urlSeance);
  http.addHeader("Content-Type", "application/json");
  http.PUT(payload);
  http.end();
  
  // Aussi sauvegarder dans pointages (pour compatibilité)
  String urlGlobal = "https://" + String(firebaseHost) + "/pointages/" + date + "/" + classeId + "/" + etuId + ".json";
  http.begin(client, urlGlobal);
  http.addHeader("Content-Type", "application/json");
  http.PUT(payload);
  http.end();
  
  Serial.print("Présence marquée: ");
  Serial.print(etuId);
  Serial.print(" - Séance: ");
  Serial.print(seanceId);
  Serial.print(" - Retard: ");
  Serial.println(enRetard ? "Oui" : "Non");
}

// ================== LOGIQUE D'ACCÈS ==================

// Réinitialise la config pour forcer un rechargement
void resetConfig() {
  configActuelle.debutHeure = -1;
  configActuelle.debutMinute = -1;
  configActuelle.retardHeure = -1;
  configActuelle.retardMinute = -1;
  configActuelle.accepterRetardataires = true;
  configActuelle.configChargee = false;
}

// Vérifie si l'élève peut entrer et ouvre la porte si autorisé
bool verifierEtOuvrirPorte(int fingerprintId) {
  String etuId = formatEtuId(fingerprintId);
  
  // Anti-spam: vérifier cooldown
  if (etuId == dernierEtuId && (millis() - dernierPointageTime) < COOLDOWN_POINTAGE) {
    Serial.println("Cooldown actif pour " + etuId);
    lcd.clear();
    lcd.print("Deja pointe!");
    lcd.setCursor(0, 1);
    lcd.print("Patientez...");
    delay(2000);
    return false;
  }
  
  // Vérifier quelle séance est en cours
  int seanceIdx = getSeanceActuelle();
  if (seanceIdx < 0) {
    Serial.println("Pas de séance en cours");
    lcd.clear();
    lcd.print("Hors seance");
    lcd.setCursor(0, 1);
    lcd.print("Porte fermee");
    delay(2000);
    return false;
  }
  
  String seanceId = seances[seanceIdx].id;
  Serial.print("Séance actuelle: ");
  Serial.println(seanceId);
  
  // Récupérer la classe de l'étudiant
  String classeId = getClasseEtudiant(etuId);
  if (classeId.isEmpty()) {
    Serial.println("Étudiant non trouvé dans Firebase");
    lcd.clear();
    lcd.print("Etudiant");
    lcd.setCursor(0, 1);
    lcd.print("non reconnu");
    delay(2000);
    return false;
  }
  
  Serial.print("Classe: ");
  Serial.println(classeId);
  
  // === CHARGER LA CONFIG DE L'ENSEIGNANT ===
  resetConfig(); // Toujours recharger pour avoir les dernières modifications
  chargerConfigSeance(classeId, seanceId);
  
  // === VÉRIFICATION 1: L'enseignant a-t-il fermé la porte ? ===
  if (!configActuelle.accepterRetardataires) {
    Serial.println("🚫 Enseignant a FERMÉ l'accès");
    lcd.clear();
    lcd.print("PORTE FERMEE");
    lcd.setCursor(0, 1);
    lcd.print("par enseignant");
    delay(3000);
    return false;
  }
  
  // === VÉRIFICATION 2: Période d'entrée ===
  bool dansPeriodeEntree = estDansPeriodeEntree(seanceIdx, classeId);
  
  if (!dansPeriodeEntree) {
    Serial.println("⏰ Hors période d'entrée autorisée");
    lcd.clear();
    lcd.print("Trop tard!");
    lcd.setCursor(0, 1);
    lcd.print("Seance " + String(seanceId));
    delay(3000);
    return false;
  }
  
  // === VÉRIFICATION 3: Absent à la séance précédente ===
  if (seanceIdx > 0) {
    bool etaitAbsent = etaitAbsentSeancePrecedente(etuId, classeId, seanceIdx);
    
    if (etaitAbsent) {
      // Vérifier s'il a un billet
      bool aBillet = aBilletPresence(etuId, seanceId);
      
      if (!aBillet) {
        Serial.println("Absent précédemment et pas de billet");
        lcd.clear();
        lcd.print("Absent " + String(seances[seanceIdx-1].id));
        lcd.setCursor(0, 1);
        lcd.print("Billet requis!");
        delay(3000);
        return false;
      }
      
      Serial.println("✅ Billet de présence valide!");
    }
  }
  
  // === ACCÈS AUTORISÉ ===
  bool enRetard = estEnRetard(seanceIdx);
  
  // Marquer la présence
  marquerPresence(fingerprintId, enRetard);
  
  // Mettre à jour le cache
  dernierEtuId = etuId;
  dernierPointageTime = millis();
  
  // Afficher et ouvrir la porte
  lcd.clear();
  if (enRetard) {
    lcd.print("EN RETARD!");
    lcd.setCursor(0, 1);
    lcd.print("Bienvenue " + String(fingerprintId));
  } else {
    lcd.print("Bienvenue!");
    lcd.setCursor(0, 1);
    lcd.print("ID: " + String(fingerprintId));
  }
  
  // Ouvrir la porte
  Serial.println(">>> OUVERTURE PORTE <<<");
  porte.write(90);
  delay(5000);
  porte.write(0);
  Serial.println(">>> FERMETURE PORTE <<<");
  
  return true;
}

// ================== FONCTIONS ENREGISTREMENT ==================

int obtenirDernierID() {
  if (WiFi.status() != WL_CONNECTED) return 1;
  
  HTTPClient http;
  WiFiClientSecure client;
  client.setInsecure();
  
  String url = "https://" + String(firebaseHost) + "/etudiants.json";
  http.begin(client, url);
  http.setTimeout(10000);
  
  int code = http.GET();
  if (code != 200) {
    http.end();
    return 1;
  }
  
  String payload = http.getString();
  http.end();
  
  if (payload == "null" || payload.length() < 5) return 1;
  
  DynamicJsonDocument doc(8192);
  DeserializationError error = deserializeJson(doc, payload);
  if (error) return 1;
  
  int maxID = 0;
  for (JsonPair kv : doc.as<JsonObject>()) {
    if (kv.value().containsKey("empreinte_id")) {
      int id = kv.value()["empreinte_id"].as<int>();
      if (id > maxID) maxID = id;
    }
  }
  
  return maxID + 1;
}

void erreur(String msg) {
  Serial.print("ERREUR: ");
  Serial.println(msg);
  lcd.clear();
  lcd.print("ERREUR");
  lcd.setCursor(0, 1);
  lcd.print(msg);
  retour = "ERREUR";
  enregistrementEnCours = false;
  idAEnregistrer = -1;
  modePointageActif = true;
  delay(3000);
  lcd.clear();
  lcd.print("Mode: POINTAGE");
}

void enregistrerEmpreinte() {
  Serial.println("\n=== ENREGISTREMENT EMPREINTE ===");
  lcd.clear();
  lcd.print("ID: ");
  lcd.print(idAEnregistrer);
  lcd.setCursor(0, 1);
  lcd.print("Doigt 1/2...");
  
  int tentatives = 0;
  while (finger.getImage() != FINGERPRINT_OK) {
    delay(100);
    tentatives++;
    if (tentatives >= 120) {
      erreur("Timeout scan 1");
      return;
    }
    yield();
  }
  
  if (finger.image2Tz(1) != FINGERPRINT_OK) {
    erreur("Erreur conv 1");
    return;
  }
  
  lcd.setCursor(0, 1);
  lcd.print("Retirez doigt  ");
  delay(1000);
  while (finger.getImage() != FINGERPRINT_NOFINGER) delay(100);
  delay(500);
  
  lcd.setCursor(0, 1);
  lcd.print("Doigt 2/2...   ");
  
  tentatives = 0;
  while (finger.getImage() != FINGERPRINT_OK) {
    delay(100);
    tentatives++;
    if (tentatives >= 120) {
      erreur("Timeout scan 2");
      return;
    }
    yield();
  }
  
  if (finger.image2Tz(2) != FINGERPRINT_OK) {
    erreur("Erreur conv 2");
    return;
  }
  
  if (finger.createModel() != FINGERPRINT_OK) {
    erreur("Erreur modele");
    return;
  }
  
  if (finger.storeModel(idAEnregistrer) == FINGERPRINT_OK) {
    lcd.clear();
    lcd.print("SUCCES!");
    lcd.setCursor(0, 1);
    lcd.print("ID: ");
    lcd.print(idAEnregistrer);
    retour = String(idAEnregistrer);
    Serial.print("Empreinte enregistrée ID: ");
    Serial.println(idAEnregistrer);
    delay(3000);
  } else {
    erreur("Erreur stockage");
    return;
  }
  
  enregistrementEnCours = false;
  idAEnregistrer = -1;
  modePointageActif = true;
  lcd.clear();
  lcd.print("Mode: POINTAGE");
}

// ================== HANDLERS SERVEUR ==================

void handleRoot() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  int seanceIdx = getSeanceActuelle();
  String seanceInfo = seanceIdx >= 0 ? seances[seanceIdx].id : "Aucune";
  
  struct tm timeinfo;
  String heureActuelle = "??:??";
  if (getLocalTime(&timeinfo)) {
    char buf[6];
    sprintf(buf, "%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min);
    heureActuelle = String(buf);
  }
  
  String html = "<html><head><meta charset='UTF-8'><meta http-equiv='refresh' content='5'>";
  html += "<style>body{font-family:Arial;margin:20px;} a{display:inline-block;padding:10px 20px;background:#FB721D;color:white;text-decoration:none;margin:5px;border-radius:5px;} a:hover{background:#e06010;}</style>";
  html += "</head><body>";
  html += "<h1>🎓 Système Pointage par Séances</h1>";
  html += "<table>";
  html += "<tr><td><b>IP ESP32:</b></td><td>" + WiFi.localIP().toString() + "</td></tr>";
  html += "<tr><td><b>Heure:</b></td><td>" + heureActuelle + "</td></tr>";
  html += "<tr><td><b>Mode:</b></td><td>" + String(modePointageActif ? "🟢 POINTAGE" : "🔵 ENREGISTREMENT") + "</td></tr>";
  html += "<tr><td><b>Séance:</b></td><td>" + seanceInfo + "</td></tr>";
  html += "<tr><td><b>Porte:</b></td><td>" + String(configActuelle.accepterRetardataires ? "🔓 Ouverte" : "🔒 Fermée") + "</td></tr>";
  html += "</table>";
  html += "<hr>";
  html += "<h3>🔧 Commandes</h3>";
  html += "<a href='/mode?m=enregistrement'>Mode ENREGISTREMENT</a>";
  html += "<a href='/mode?m=detection'>Mode DETECTION</a><br><br>";
  html += "<a href='/enregistrer'>Démarrer enregistrement</a>";
  html += "<a href='/resultat'>Voir résultat</a><br><br>";
  html += "<a href='/seance'>Info séance</a>";
  html += "<a href='/porte?action=ouvrir'>🚪 TEST PORTE</a><br><br>";
  html += "<a href='/vider' style='background:red;'>⚠️ VIDER CAPTEUR</a>";
  html += "</body></html>";
  
  server.send(200, "text/html", html);
}

void handleMode() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (server.hasArg("m")) {
    String m = server.arg("m");
    if (m == "enregistrement") {
      modePointageActif = false;
      enregistrementEnCours = false;
      lcd.clear();
      lcd.print("Mode: ENREGISTRE");
      server.send(200, "text/plain", "MODE_ENREGISTREMENT");
    } else if (m == "detection") {
      modePointageActif = true;
      enregistrementEnCours = false;
      lcd.clear();
      lcd.print("Mode: POINTAGE");
      server.send(200, "text/plain", "MODE_DETECTION");
    } else {
      server.send(400, "text/plain", "MODE_INCONNU");
    }
  } else {
    server.send(400, "text/plain", "PARAM_M_MANQUANT");
  }
}

void handleEnregistrer() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (enregistrementEnCours) {
    server.send(200, "text/plain", "DEJA_EN_COURS");
    return;
  }
  
  modePointageActif = false;
  idAEnregistrer = obtenirDernierID();
  enregistrementEnCours = true;
  retour = "EN_ATTENTE";
  
  lcd.clear();
  lcd.print("ID: ");
  lcd.print(idAEnregistrer);
  lcd.setCursor(0, 1);
  lcd.print("Placez le doigt");
  
  server.send(200, "text/plain", String(idAEnregistrer));
}

void handleResultat() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "text/plain", retour);
}

void handleSeance() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  int seanceIdx = getSeanceActuelle();
  
  DynamicJsonDocument doc(512);
  
  if (seanceIdx >= 0) {
    doc["seance_id"] = seances[seanceIdx].id;
    doc["debut"] = String(seances[seanceIdx].debutHeure) + ":" + String(seances[seanceIdx].debutMinute);
    doc["fin"] = String(seances[seanceIdx].finHeure) + ":" + String(seances[seanceIdx].finMinute);
    doc["retard_limite"] = String(seances[seanceIdx].retardHeure) + ":" + String(seances[seanceIdx].retardMinute);
    // Note: estDansPeriodeEntree nécessite classeId, on met une valeur par défaut ici
    doc["dans_periode_entree"] = estDansPeriodeEntree(seanceIdx, "");
  } else {
    doc["seance_id"] = nullptr;
    doc["message"] = "Pas de séance en cours";
  }
  
  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
}

void handleVider() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  lcd.clear();
  lcd.print("VIDAGE...");
  
  uint8_t p = finger.emptyDatabase();
  
  if (p == FINGERPRINT_OK) {
    lcd.clear();
    lcd.print("VIDE OK!");
    delay(2000);
    server.send(200, "text/plain", "CAPTEUR_VIDE");
  } else {
    lcd.clear();
    lcd.print("ERREUR vidage");
    delay(2000);
    server.send(500, "text/plain", "ERREUR_VIDAGE");
  }
  
  lcd.clear();
  lcd.print("Mode: POINTAGE");
}

// Endpoint pour tester la porte directement
void handlePorte() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (server.hasArg("action")) {
    String action = server.arg("action");
    
    if (action == "ouvrir") {
      Serial.println("🚪 Ouverture porte (test)");
      lcd.clear();
      lcd.print("PORTE OUVERTE");
      lcd.setCursor(0, 1);
      lcd.print("(test manuel)");
      porte.write(90);
      delay(5000);
      porte.write(0);
      lcd.clear();
      lcd.print("PORTE FERMEE");
      server.send(200, "text/plain", "PORTE_OUVERTE_FERMEE");
    } else if (action == "fermer") {
      Serial.println("🚪 Fermeture porte (test)");
      porte.write(0);
      lcd.clear();
      lcd.print("PORTE FERMEE");
      server.send(200, "text/plain", "PORTE_FERMEE");
    } else {
      server.send(400, "text/plain", "ACTION_INCONNUE");
    }
  } else {
    server.send(400, "text/plain", "PARAM_ACTION_MANQUANT");
  }
}

// Endpoint pour recharger la config
void handleReloadConfig() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (server.hasArg("classe") && server.hasArg("seance")) {
    String classeId = server.arg("classe");
    String seanceId = server.arg("seance");
    
    resetConfig();
    chargerConfigSeance(classeId, seanceId);
    
    DynamicJsonDocument doc(256);
    doc["accepter_retardataires"] = configActuelle.accepterRetardataires;
    if (configActuelle.debutHeure >= 0) {
      doc["heure_debut"] = String(configActuelle.debutHeure) + ":" + String(configActuelle.debutMinute);
    }
    if (configActuelle.retardHeure >= 0) {
      doc["retard_limite"] = String(configActuelle.retardHeure) + ":" + String(configActuelle.retardMinute);
    }
    
    String output;
    serializeJson(doc, output);
    server.send(200, "application/json", output);
  } else {
    server.send(400, "text/plain", "PARAMS_MANQUANTS");
  }
}

// ================== SETUP ==================

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=== SYSTÈME POINTAGE PAR SÉANCES ===");
  
  // LCD
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.print("Initialisation...");
  
  // Capteur empreinte
  fingerSerial.begin(57600, SERIAL_8N1, 16, 17);
  finger.begin(57600);
  if (!finger.verifyPassword()) {
    Serial.println("Capteur d'empreinte non détecté!");
    lcd.clear();
    lcd.print("CAPTEUR KO!");
    while (1) delay(1000);
  }
  Serial.println("Capteur d'empreinte OK");
  
  // Servo
  porte.attach(14);
  porte.write(0);
  
  // WiFi
  Serial.println("Connexion WiFi...");
  lcd.clear();
  lcd.print("Connexion WiFi");
  
  WiFi.setSleep(false);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);
  WiFi.begin(ssid, password);
  
  int tentatives = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    tentatives++;
    if (tentatives >= 60) {
      WiFi.disconnect();
      delay(1000);
      WiFi.begin(ssid, password, 1);
      delay(2000);
      tentatives = 0;
    }
  }
  
  Serial.println("\nWiFi connecté!");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());
  
  lcd.clear();
  lcd.print("WiFi OK!");
  lcd.setCursor(0, 1);
  lcd.print(WiFi.localIP());
  delay(2000);
  
  // NTP
  configTime(3600, 0, "pool.ntp.org", "time.nist.gov");
  
  // Serveur web
  server.on("/", HTTP_GET, handleRoot);
  server.on("/mode", HTTP_GET, handleMode);
  server.on("/enregistrer", HTTP_GET, handleEnregistrer);
  server.on("/resultat", HTTP_GET, handleResultat);
  server.on("/seance", HTTP_GET, handleSeance);
  server.on("/vider", HTTP_GET, handleVider);
  server.on("/porte", HTTP_GET, handlePorte);       // Test porte
  server.on("/config", HTTP_GET, handleReloadConfig); // Recharger config
  server.begin();
  
  lcd.clear();
  int seanceIdx = getSeanceActuelle();
  if (seanceIdx >= 0) {
    lcd.print("Seance: ");
    lcd.print(seances[seanceIdx].id);
  } else {
    lcd.print("Hors seance");
  }
  lcd.setCursor(0, 1);
  lcd.print("Pret!");
  
  Serial.println("=== SYSTÈME PRÊT ===");
}

// ================== LOOP ==================

void loop() {
  server.handleClient();
  
  // Reconnexion WiFi si nécessaire
  static unsigned long lastCheck = 0;
  if (millis() - lastCheck > 10000) {
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi déconnecté, reconnexion...");
      WiFi.reconnect();
    }
    lastCheck = millis();
    
    // Mettre à jour l'affichage de la séance
    int seanceIdx = getSeanceActuelle();
    if (modePointageActif && !enregistrementEnCours) {
      lcd.setCursor(0, 0);
      if (seanceIdx >= 0) {
        lcd.print("Seance: ");
        lcd.print(seances[seanceIdx].id);
        lcd.print("    ");
      } else {
        lcd.print("Hors seance     ");
      }
    }
  }
  
  // Mode pointage
  if (modePointageActif && !enregistrementEnCours) {
    if (finger.getImage() == FINGERPRINT_OK) {
      if (finger.image2Tz() == FINGERPRINT_OK) {
        if (finger.fingerFastSearch() == FINGERPRINT_OK) {
          int id = finger.fingerID;
          Serial.print("Empreinte détectée - ID: ");
          Serial.println(id);
          
          // Vérifier l'accès et ouvrir la porte si autorisé
          verifierEtOuvrirPorte(id);
          
          delay(2000);
          lcd.clear();
          int seanceIdx = getSeanceActuelle();
          if (seanceIdx >= 0) {
            lcd.print("Seance: ");
            lcd.print(seances[seanceIdx].id);
          } else {
            lcd.print("Hors seance");
          }
          lcd.setCursor(0, 1);
          lcd.print("Pret!");
        } else {
          Serial.println("Empreinte non reconnue");
          lcd.clear();
          lcd.print("Non reconnu!");
          lcd.setCursor(0, 1);
          lcd.print("Porte fermee");
          delay(2000);
          lcd.clear();
          int seanceIdx = getSeanceActuelle();
          if (seanceIdx >= 0) {
            lcd.print("Seance: ");
            lcd.print(seances[seanceIdx].id);
          } else {
            lcd.print("Hors seance");
          }
          lcd.setCursor(0, 1);
          lcd.print("Pret!");
        }
      }
    }
  }
  
  // Mode enregistrement
  if (enregistrementEnCours) {
    enregistrerEmpreinte();
  }
}


