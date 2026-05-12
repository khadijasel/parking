// ════════════════════════════════════════════════════════════
//  SmartPark.ino — Fichier principal
//  Carte : ESP32 WROVER-Dev
//
//  Matériel :
//    • 1× LCD 16×2 I2C (0x27)  SDA=GPIO21  SCL=GPIO22
//    • 6× LED jaune (allumée = RÉSERVÉ via API)
//        A1=GPIO23  A2=GPIO25  A3=GPIO26
//        B1=GPIO12  B2=GPIO2   B3=GPIO16 (⚠ PSRAM→Disabled dans IDE)
//    • 6× Capteur IR FC-51 (LOW = voiture présente)
//        A1=GPIO15  A2=GPIO27  A3=GPIO32
//        B1=GPIO33  B2=GPIO34  B3=GPIO35
//    • 2× HC-SR04  TRIG/ECHO avec pont diviseur (ECHO 5V→3.3V)
//        Entrée : TRIG=GPIO4   ECHO=GPIO5
//        Sortie : TRIG=GPIO18  ECHO=GPIO19
//        ⚠️ GPIO 16/17 INTERDITS sur WROVER (PSRAM)
//    • 2× Servo SG90
//        Entrée = GPIO13   Sortie = GPIO14
//
//  Arduino IDE :
//    Board          → ESP32 Wrover Module
//    Partition      → Huge APP (3MB No OTA)
//    PSRAM          → Enabled
//    Upload Speed   → 921600
//    Serial Monitor → 115200
//
//  Bibliothèques requises (Manage Libraries) :
//    • ESP32Servo        (Kevin Harrington)
//    • LiquidCrystal I2C (Frank de Brabander)
//    • ArduinoJson v6    (Benoit Blanchon)
// ════════════════════════════════════════════════════════════

#include "../lib/config/config.h"
#include "../lib/parking/parking_state.h"
#include "../lib/sensors/ir_sensor.h"
#include "../lib/sensors/ultrasonic.h"
#include "../lib/actuators/barrier.h"
#include "../lib/actuators/led_manager.h"
#include "../lib/display/display_manager.h"
#include "../lib/network/api_client.h"

// ── Instances globales ────────────────────────────────────────
ParkingState  state;
IrManager     ir;
Ultrasonic    usEntry(TRIG_ENTREE, ECHO_ENTREE, "Entree");
Ultrasonic    usExit (TRIG_SORTIE, ECHO_SORTIE, "Sortie");
Barrier       gateIn (SERVO_ENTREE, "Entree");
Barrier       gateOut(SERVO_SORTIE, "Sortie");
LedManager    leds;
DisplayManager lcd;
ApiClient     api;

// ── Timers tâches ─────────────────────────────────────────────
unsigned long tPoll = 0, tApi = 0, tLcd = 0;

// ── États précédents ultrason (détection front montant) ───────
bool prevEntry = false, prevExit = false;

// ════════════════════════════════════════════════════════════
//  ÉVÉNEMENTS SÉRIE (Python listener)
//
//  But : émettre une ligne JSON simple et ASCII (sans accents)
//  pour que python/serial_listener.py puisse détecter l'entrée.
//  Exemple : {"event":"entry","parking_id":"arduino-sim"}
// ════════════════════════════════════════════════════════════
void emitSerialEvent(const char* eventName, const char* spotLabel = nullptr) {
  Serial.print("{\"event\":\"");
  Serial.print(eventName);
  Serial.print("\",\"parking_id\":\"");
  Serial.print(PARKING_ID);

  if (spotLabel != nullptr && spotLabel[0] != '\0') {
    Serial.print("\",\"spot_label\":\"");
    Serial.print(spotLabel);
  }

  Serial.println("\"}");
}

// ════════════════════════════════════════════════════════════
//  SETUP
// ════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(BAUD_RATE);
  delay(500);

  Serial.println();
  Serial.println("╔══════════════════════════════╗");
  Serial.println("║   SmartPark — WROVER-Dev     ║");
  Serial.printf ("║   Chip : %-20s║\n", ESP.getChipModel());
  Serial.printf ("║   PSRAM: %-4d KB  Flash: %-4d║\n",
    ESP.getPsramSize()/1024, ESP.getFlashChipSize()/1024);
  Serial.println("╚══════════════════════════════╝\n");

  // 1. État initial
  initState(state);

  // 2. Capteurs
  ir.begin();
  usEntry.begin();
  usExit.begin();

  // 3. Actionneurs
  leds.begin();
  gateIn.begin();
  gateOut.begin();
  gateIn.test();
  gateOut.test();

  // 4. Écran LCD
  // lcd.begin();  // DÉSACTIVÉ TEMPORAIREMENT pour diagnostic

  // 5. WiFi + sync API initiale
  state.wifiOk = api.connectWifi();
  if (state.wifiOk) {
    api.sendInfraredReadings(state);
  } else {
    delay(1500);
  }

  // 6. Lecture initiale IR + mise à jour LEDs
  ir.update(state);
  leds.update(state);

  Serial.printf("\n[READY] Places libres : %d/%d\n\n",
    state.freeCnt, NB_PLACES);
}

// ════════════════════════════════════════════════════════════
//  LOOP
// ════════════════════════════════════════════════════════════
void loop() {
  unsigned long now = millis();

  // ── A. Lecture capteurs (IR + Ultrason) ───────────────────
  if (now - tPoll >= POLL_MS) {
    tPoll = now;
    taskSensors();
  }

  // ── B. Synchronisation API (batch IR toutes les API_MS) ───
  if (now - tApi >= API_MS) {
    tApi = now;
    taskApi();
  }

  // ── C. Fermeture automatique barrières (continu) ─────────
  gateIn.tick();
  gateOut.tick();
  state.gateInOpen  = gateIn.isOpen();
  state.gateOutOpen = gateOut.isOpen();

  yield(); // laisse le WiFi traiter ses paquets
}

// ════════════════════════════════════════════════════════════
//  TÂCHE A — Capteurs IR + Ultrason
// ════════════════════════════════════════════════════════════
void taskSensors() {

  // ── IR : état des 6 places ─────────────────────────────────
  if (ir.update(state)) {
    leds.update(state);
    if (state.wifiOk) {
      api.sendInfraredReadings(state); // envoi immédiat sur changement
    }
  }

  // ── Ultrason ENTRÉE ────────────────────────────────────────
  bool nowEntry = usEntry.detect();

  // ── Ultrason SORTIE ────────────────────────────────────────
  bool nowExit = usExit.detect();

  Serial.printf("[SENSOR] Entry: %s | Exit: %s\n", nowEntry ? "OUI" : "NON", nowExit ? "OUI" : "NON");

  if (nowEntry && !prevEntry) onCarEntry();   // front montant
  prevEntry = nowEntry;
  state.carAtEntry = nowEntry;

  if (nowExit && !prevExit) onCarExit();     // front montant
  prevExit = nowExit;
  state.carAtExit = nowExit;
}

// ════════════════════════════════════════════════════════════
//  TÂCHE B — Synchronisation API
// ════════════════════════════════════════════════════════════
void taskApi() {
  if (!api.isUp()) {
    Serial.println("[WIFI] Reconnexion...");
    state.wifiOk = api.connectWifi();
    return;
  }

  // Envoi batch des 6 capteurs IR vers Laravel
  api.sendInfraredReadings(state);
}

// ════════════════════════════════════════════════════════════
//  ÉVÉNEMENT : VOITURE DÉTECTÉE À L'ENTRÉE
// ════════════════════════════════════════════════════════════
void onCarEntry() {
  Serial.println("[EVENT] ─── Voiture ENTRÉE ───");

  // Parking complet ?
  if (state.freeCnt <= 0) {
    Serial.println("[EVENT] Parking COMPLET → refus");
    lcd.showFull();
    leds.alert(5, 100);
    return;
  }

  // Ouvrir barrière entrée
  gateIn.open();

  // Afficher place conseillée sur LCD
  int fi = firstFree(state);
  if (fi >= 0) {
    char l2[17];
    snprintf(l2, sizeof(l2), " Place libre: %s ", state.spots[fi].label);
    lcd.msg("  Bienvenue !   ", l2);
    Serial.printf("[EVENT] Place conseillée : %s\n",
      state.spots[fi].label);
  } else {
    lcd.msg("  Bienvenue !   ", "  Bonne place ! ");
  }

  // Event machine-readable pour le générateur Python (1 seule ligne par entrée)
  emitSerialEvent("entry", (fi >= 0) ? state.spots[fi].label : nullptr);

  // Démarrer session dans Laravel
  // La session est gérée côté app/backend, l'ESP32 ne l'initie plus ici.
}

// ════════════════════════════════════════════════════════════
//  ÉVÉNEMENT : VOITURE DÉTECTÉE À LA SORTIE
// ════════════════════════════════════════════════════════════
void onCarExit() {
  Serial.println("[EVENT] ─── Voiture SORTIE ───");

  // Event série utile si on veut plus tard automatiser une logique côté PC.
  emitSerialEvent("exit");

  // Ouvrir barrière sortie
  gateOut.open();
  lcd.msg(" Bonne route !  ", "   Merci !      ");

  // Pas d'appel session backend ici.
}
