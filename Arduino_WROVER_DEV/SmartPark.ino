// ════════════════════════════════════════════════════════════
//  SmartPark.ino — Fichier principal
//  Carte : ESP32 WROVER-Dev
//
//  Matériel :
//    • 1× LCD 16×2 I2C (0x27)  SDA=GPIO21  SCL=GPIO22
//    • 6× LED jaune (réservation)
//        A1=GPIO21 A2=GPIO22 A3=GPIO23
//        B1=GPIO2  B2=GPIO0  B3=GPIO12
//    • 6× Capteur IR FC-51
//        A1=GPIO25 A2=GPIO26 A3=GPIO27
//        B1=GPIO32 B2=GPIO33 B3=GPIO15
//    • 2× HC-SR04  TRIG/ECHO avec pont diviseur
//        Entrée : TRIG=GPIO4  ECHO=GPIO5
//        Sortie : TRIG=GPIO18 ECHO=GPIO19
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

#include "lib/config/config.h"
#include "lib/parking/parking_state.h"
#include "lib/sensors/ir_sensor.h"
#include "lib/sensors/ultrasonic.h"
#include "lib/actuators/barrier.h"
#include "lib/actuators/led_manager.h"
#include "lib/display/display_manager.h"
#include "lib/network/api_client.h"

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
  lcd.begin();

  // 5. WiFi + sync API
  lcd.showWifiWait();
  state.wifiOk = api.connectWifi();

  if (state.wifiOk) {
    lcd.showWifiOk(api.ip());
    api.sendInfraredReadings(state);  // synchroniser l'état IR initial
  } else {
    lcd.showWifiErr();
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

  // ── A. Lecture capteurs ───────────────────────────────────
  if (now - tPoll >= POLL_MS) {
    tPoll = now;
    taskSensors();
  }

  // ── B. Synchronisation API ────────────────────────────────
  if (now - tApi >= API_MS) {
    tApi = now;
    taskApi();
  }

  // ── C. Rafraîchissement LCD ───────────────────────────────
  if (now - tLcd >= LCD_MS) {
    tLcd = now;
    lcd.tick(state);
  }

  // ── D. Fermeture automatique barrières (continu) ─────────
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
  }

  // ── Ultrason ENTRÉE ────────────────────────────────────────
  bool nowEntry = usEntry.detect();
  if (nowEntry && !prevEntry) onCarEntry();   // front montant
  prevEntry = nowEntry;
  state.carAtEntry = nowEntry;

  // ── Ultrason SORTIE ────────────────────────────────────────
  bool nowExit = usExit.detect();
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

  // Démarrer session dans Laravel
  // La session est gérée côté app/backend, l'ESP32 ne l'initie plus ici.
}

// ════════════════════════════════════════════════════════════
//  ÉVÉNEMENT : VOITURE DÉTECTÉE À LA SORTIE
// ════════════════════════════════════════════════════════════
void onCarExit() {
  Serial.println("[EVENT] ─── Voiture SORTIE ───");

  // Ouvrir barrière sortie
  gateOut.open();
  lcd.msg(" Bonne route !  ", "   Merci !      ");

  // Pas d'appel session backend ici.
}
