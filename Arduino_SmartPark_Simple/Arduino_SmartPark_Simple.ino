#include <Wire.h>

// ════════════════════════════════════════════════════════════
//  SmartPark — ESP32 connecté au backend Laravel
//
//  Câblage :
//    • HC-SR04 ENTREE  : TRIG=GPIO4   ECHO=GPIO5
//    • HC-SR04 SORTIE  : TRIG=GPIO18  ECHO=GPIO19
//    • Servos          : SERVO_IN=13  SERVO_OUT=14
//    • IR x6           : 15, 27, 32, 33, 34, 35  → places chargées depuis DB
//    • LEDs (1/place)  : 23, 25, 26, 12, 2, 16   (LED ON = place occupée)
//    • LCD I2C 0x27    : SDA=GPIO21   SCL=GPIO22
//
//  WiFi : SSID="khadija"  Pass="khadija17"
//
//  Endpoints Laravel :
//    GET  /api/parkings/{id}/spots        → labels des places depuis DB
//    POST /api/parkings/infrared/readings → état des IR + réponse avec spots
//    POST /api/iot/tickets                → ticket à l'entrée
//  Header IoT : X-Sensor-Key / X-Arduino-Key
//
//  Bibliothèques :
//    ESP32Servo · LiquidCrystal I2C · ArduinoJson v6
// ════════════════════════════════════════════════════════════

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <LiquidCrystal_I2C.h>

/* ===================== CONFIG ===================== */

// HC-SR04
#define TRIG_IN   4
#define ECHO_IN   5
#define TRIG_OUT  18
#define ECHO_OUT  19
#define DIST_TRIGGER_CM 10

// Servos
#define SERVO_IN  13
#define SERVO_OUT 14
#define SERVO_OPEN_DEG  90
#define SERVO_CLOSE_DEG 0
#define BARRIER_OPEN_MS 3500

// IR pins (LOW = place occupée)
const int IR_PINS[6] = {15, 27, 32, 33, 34, 35};

// LEDs (1 LED par place, ON = occupée)
// ⚠ GPIO 16 = PSRAM sur ESP32 WROVER → -1 si crash au boot
// ⚠ GPIO 12 = strap-pin → -1 si crash
const int LED_PINS[6] = {23, 25, 26, 12, 2, -1};

// LCD
#define LCD_SDA  21
#define LCD_SCL  22
#define LCD_ADDR 0x27

// WiFi
#define WIFI_SSID       "khadija"
#define WIFI_PASSWORD   "khadija17"
#define WIFI_TIMEOUT_MS 15000

// Backend Laravel
#define API_BASE_URL    "http://10.133.226.121:8000/api"
#define ARDUINO_API_KEY "smartpark_iot_secret_key_2024"
#define PARKING_ID      "arduino-sim"
#define PARKING_NAME    "Notre Parking"
#define DEVICE_ID       "ESP32-SmartPark"
#define API_TIMEOUT_MS  3000   // réduit de 8s → 3s pour une réponse rapide

// Cadences (non-bloquantes)
#define POLL_MS          300
#define SYNC_MS         1000   // refresh chaque 1 seconde
#define LCD_MS          1000
#define ENTRY_DEBOUNCE  4000
#define WIFI_RETRY_MS  10000

/* ===================== PLACES DYNAMIQUES ===================== */

#define MAX_SPOTS 12
// Labels dans l'ordre physique des pins IR : ir[0]..ir[5]
//   ir[0]=GPIO15 → P5   ir[1]=GPIO27 → P6   ir[2]=GPIO32 → P3
//   ir[3]=GPIO33 → P4   ir[4]=GPIO34 → A1   ir[5]=GPIO35 → P2
char  spotLabels[MAX_SPOTS][16] = {"P5","P6","P3","P4","A1","P2"};
int   numSpots = 6;

/* ===================== ÉTAT GLOBAL ===================== */

Servo servoIn;
Servo servoOut;
LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);

bool occupied[MAX_SPOTS] = {};
bool occSent[MAX_SPOTS]  = {};

bool carIn = false,  carOut = false;
bool prevIn = false, prevOut = false;

bool gateInOpen  = false, gateOutOpen = false;
unsigned long gateInOpenedAt  = 0;
unsigned long gateOutOpenedAt = 0;

bool wifiOk = false;
unsigned long tPoll = 0, tSync = 0, tLcd = 0;
unsigned long tLastEntryPost = 0;
unsigned long tLastWifiRetry = 0;
bool firstSync = true;

// Première place libre confirmée par le backend après chaque sync
char backendFirstFreeSpot[16] = "";

/* ===================== HELPERS ===================== */

float readDistance(int trig, int echo) {
  digitalWrite(trig, LOW);
  delayMicroseconds(2);
  digitalWrite(trig, HIGH);
  delayMicroseconds(10);
  digitalWrite(trig, LOW);
  long duration = pulseIn(echo, HIGH, 30000);
  return duration * 0.034f / 2.0f;
}

int countOccupied() {
  int n = 0;
  for (int i = 0; i < numSpots; i++) if (occupied[i]) n++;
  return n;
}

// Fallback local si le backend n'a pas encore répondu
const char* firstFreeLocal() {
  for (int i = 0; i < numSpots; i++) if (!occupied[i]) return spotLabels[i];
  return nullptr;
}

/* ===================== WIFI ===================== */

bool connectWifi() {
  Serial.printf("[WiFi] Connexion a \"%s\"", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - t0 > WIFI_TIMEOUT_MS) {
      Serial.println("\n[WiFi] Timeout — hors ligne");
      return false;
    }
    delay(400);
    Serial.print(".");
  }
  Serial.printf("\n[WiFi] OK  IP=%s  RSSI=%d dBm\n",
                WiFi.localIP().toString().c_str(), WiFi.RSSI());
  return true;
}

bool ensureWifi() {
  if (WiFi.status() == WL_CONNECTED) { wifiOk = true; return true; }
  unsigned long now = millis();
  if (now - tLastWifiRetry < WIFI_RETRY_MS) return false;
  tLastWifiRetry = now;
  wifiOk = connectWifi();
  return wifiOk;
}

/* ===================== HTTP POST ===================== */

// Retourne le code HTTP. Si responseOut != nullptr et code 2xx, stocke le body.
int httpPostJson(const char* path, const String& body, String* responseOut = nullptr) {
  if (WiFi.status() != WL_CONNECTED) return -1;
  HTTPClient http;
  http.begin(String(API_BASE_URL) + path);
  http.setTimeout(API_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  http.addHeader("X-Sensor-Key",  ARDUINO_API_KEY);
  http.addHeader("X-Arduino-Key", ARDUINO_API_KEY);
  http.addHeader("X-IoT-Key",     ARDUINO_API_KEY);
  int code = http.POST(body);
  if (code <= 0) {
    Serial.printf("[HTTP] POST %s ERR %s\n", path, http.errorToString(code).c_str());
  } else {
    Serial.printf("[HTTP] POST %s -> %d\n", path, code);
    if (responseOut && (code == 200 || code == 201)) {
      *responseOut = http.getString();
    }
  }
  http.end();
  return code;
}

/* ===================== VÉRIFICATION PLACES DEPUIS LA DB ===================== */

// Appel au démarrage : GET /api/parkings/{PARKING_ID}/spots
// N'écrase PAS spotLabels[] — l'ordre physique des câblage IR est fixé par
// le matériel et doit rester intact. On affiche juste le nombre de places
// retournées par la DB pour vérification en console.
bool fetchSpotsFromBackend() {
  if (WiFi.status() != WL_CONNECTED) return false;

  HTTPClient http;
  String url = String(API_BASE_URL) + "/parkings/" + PARKING_ID + "/spots";
  http.begin(url);
  http.setTimeout(API_TIMEOUT_MS);
  http.addHeader("Accept", "application/json");
  int code = http.GET();

  if (code != 200) {
    Serial.printf("[Spots] GET %s -> %d\n", url.c_str(), code);
    http.end();
    return false;
  }

  String payload = http.getString();
  http.end();

  DynamicJsonDocument doc(2048);
  if (deserializeJson(doc, payload) != DeserializationError::Ok) {
    Serial.println("[Spots] Erreur parse JSON");
    return false;
  }

  JsonArray spots = doc["data"];
  int count = spots.isNull() ? 0 : (int)spots.size();
  Serial.printf("[Spots] DB contient %d places (câblage physique garde)\n", count);
  Serial.print("[Spots] Ordre physique IR: ");
  for (int i = 0; i < numSpots; i++) Serial.printf("ir[%d]=%s ", i, spotLabels[i]);
  Serial.println();
  return count > 0;
}

/* ===================== SYNC BACKEND (IR + PREMIERE PLACE LIBRE) ===================== */

// Envoie l'état IR, lit la réponse pour obtenir la première place AVAILABLE
// selon la DB (pas seulement le capteur local).
bool syncWithBackend() {
  // Construction du payload IR
  StaticJsonDocument<512> req;
  req["parking_id"] = PARKING_ID;
  req["device_id"]  = DEVICE_ID;
  JsonArray arr = req.createNestedArray("readings");
  for (int i = 0; i < numSpots; i++) {
    JsonObject r = arr.createNestedObject();
    r["spot_label"] = spotLabels[i];
    r["occupied"]   = occupied[i];
  }
  String body;
  serializeJson(req, body);

  String responseBody;
  int code = httpPostJson("/parkings/infrared/readings", body, &responseBody);

  if (code != 200 && code != 201) return false;

  // Marquer comme envoyé
  for (int i = 0; i < numSpots; i++) occSent[i] = occupied[i];

  // Parser la réponse pour trouver la première place AVAILABLE côté backend
  backendFirstFreeSpot[0] = '\0';

  if (responseBody.length() > 0) {
    DynamicJsonDocument resp(4096);
    if (deserializeJson(resp, responseBody) == DeserializationError::Ok) {
      // La réponse contient data.spots[] avec le champ state mis à jour
      JsonArray spots = resp["data"]["spots"];
      if (!spots.isNull()) {
        for (JsonObject spot : spots) {
          const char* state = spot["state"] | "";
          // Comparaison insensible à la casse
          if (strcasecmp(state, "AVAILABLE") == 0) {
            const char* lbl = spot["label"] | "";
            if (strlen(lbl) > 0) {
              strlcpy(backendFirstFreeSpot, lbl, sizeof(backendFirstFreeSpot));
              break;
            }
          }
        }
      }
    }
  }

  Serial.printf("[Sync] OK  firstFree=%s\n",
    backendFirstFreeSpot[0] ? backendFirstFreeSpot : "(none)");
  return true;
}

/* ===================== TICKET D'ENTREE ===================== */

bool postEntryTicket(const char* spotLabel) {
  StaticJsonDocument<256> doc;
  doc["parking_id"]   = PARKING_ID;
  doc["parking_name"] = PARKING_NAME;
  if (spotLabel && spotLabel[0] != '\0') doc["spot_label"] = spotLabel;
  String body;
  serializeJson(doc, body);
  int code = httpPostJson("/iot/tickets", body);
  return (code == 200 || code == 201);
}

/* ===================== HARDWARE ===================== */

void readIrSensors() {
  for (int i = 0; i < numSpots; i++) {
    occupied[i] = (digitalRead(IR_PINS[i]) == LOW);
  }
}

void updateSpotLeds() {
  for (int i = 0; i < numSpots && i < 6; i++) {
    if (LED_PINS[i] < 0) continue;
    digitalWrite(LED_PINS[i], occupied[i] ? HIGH : LOW);
  }
}

void openEntryGate() {
  servoIn.write(SERVO_OPEN_DEG);
  gateInOpen     = true;
  gateInOpenedAt = millis();
}

void openExitGate() {
  servoOut.write(SERVO_OPEN_DEG);
  gateOutOpen     = true;
  gateOutOpenedAt = millis();
}

void tickGates() {
  unsigned long now = millis();
  if (gateInOpen  && now - gateInOpenedAt  > BARRIER_OPEN_MS) {
    servoIn.write(SERVO_CLOSE_DEG);  gateInOpen  = false;
  }
  if (gateOutOpen && now - gateOutOpenedAt > BARRIER_OPEN_MS) {
    servoOut.write(SERVO_CLOSE_DEG); gateOutOpen = false;
  }
}

void renderLcd(int nOccupied, int nFree) {
  lcd.setCursor(0, 0);
  lcd.print("Smart Parking   ");
  lcd.setCursor(0, 1);
  lcd.print("                ");
  lcd.setCursor(0, 1);
  if (nOccupied >= numSpots) {
    lcd.print("Parking plein");
  } else {
    lcd.print(nOccupied);
    lcd.print("/");
    lcd.print(numSpots);
    lcd.print(" Lib:");
    lcd.print(nFree);
  }
}

/* ===================== ÉVÉNEMENTS ===================== */

void onCarEntry() {
  int nFree = numSpots - countOccupied();
  Serial.printf("[EVENT] Voiture ENTREE  (libre=%d)\n", nFree);

  if (nFree <= 0) {
    Serial.println("[EVENT] Parking COMPLET — refus");
    lcd.setCursor(0, 1);
    lcd.print("Parking COMPLET ");
    return;
  }

  openEntryGate();

  // Utiliser la place libre confirmée par la DB (dernière sync)
  // Si la DB n'a pas encore répondu, fallback sur l'état IR local
  const char* suggested = nullptr;
  if (backendFirstFreeSpot[0] != '\0') {
    suggested = backendFirstFreeSpot;
    Serial.printf("[EVENT] Place suggérée (DB): %s\n", suggested);
  } else {
    suggested = firstFreeLocal();
    Serial.printf("[EVENT] Place suggérée (IR local): %s\n",
      suggested ? suggested : "aucune");
  }

  lcd.setCursor(0, 0);
  lcd.print("  Bienvenue !   ");
  lcd.setCursor(0, 1);
  char buf[17];
  if (suggested) snprintf(buf, sizeof(buf), " Place libre:%s ", suggested);
  else           snprintf(buf, sizeof(buf), "  Bonne place ! ");
  lcd.print(buf);

  if (ensureWifi()) postEntryTicket(suggested);
}

void onCarExit() {
  Serial.println("[EVENT] Voiture SORTIE");
  openExitGate();
  lcd.setCursor(0, 0);
  lcd.print(" Bonne route !  ");
  lcd.setCursor(0, 1);
  lcd.print("    Merci !     ");
}

/* ===================== SETUP / LOOP ===================== */

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== SmartPark ESP32 ===");

  // HC-SR04
  pinMode(TRIG_IN,  OUTPUT);  pinMode(ECHO_IN,  INPUT);
  pinMode(TRIG_OUT, OUTPUT);  pinMode(ECHO_OUT, INPUT);

  // IR
  for (int i = 0; i < 6; i++) pinMode(IR_PINS[i], INPUT);

  // LEDs
  for (int i = 0; i < 6; i++) {
    if (LED_PINS[i] < 0) continue;
    pinMode(LED_PINS[i], OUTPUT);
    digitalWrite(LED_PINS[i], LOW);
  }

  // Servos
  servoIn.attach(SERVO_IN);
  servoOut.attach(SERVO_OUT);
  servoIn.write(SERVO_CLOSE_DEG);
  servoOut.write(SERVO_CLOSE_DEG);

  // LCD
  Wire.begin(LCD_SDA, LCD_SCL);
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0); lcd.print("Smart Parking   ");
  lcd.setCursor(0, 1); lcd.print("WiFi ...        ");

  // WiFi
  wifiOk = connectWifi();
  lcd.setCursor(0, 1);
  lcd.print(wifiOk ? "WiFi OK         " : "WiFi off-line   ");
  delay(800);

  if (wifiOk) {
    // 1. Charger les noms des places depuis la base de données
    lcd.setCursor(0, 1);
    lcd.print("Chargement DB...");
    if (!fetchSpotsFromBackend()) {
      Serial.println("[Setup] Utilisation des labels par defaut (A1-B3)");
    }

    // 2. Lecture initiale + premier sync
    readIrSensors();
    updateSpotLeds();
    syncWithBackend();
    firstSync = false;
  }
}

void loop() {
  unsigned long now = millis();

  // ── A. Lecture capteurs ─────────────────────────────────
  if (now - tPoll >= POLL_MS) {
    tPoll = now;

    readIrSensors();
    updateSpotLeds();

    float dIn  = readDistance(TRIG_IN,  ECHO_IN);
    float dOut = readDistance(TRIG_OUT, ECHO_OUT);
    carIn  = (dIn  > 0 && dIn  < DIST_TRIGGER_CM);
    carOut = (dOut > 0 && dOut < DIST_TRIGGER_CM);

    int nOcc  = countOccupied();
    int nFree = numSpots - nOcc;

    // Front montant entrée → ticket
    if (carIn && !prevIn && (now - tLastEntryPost > ENTRY_DEBOUNCE)) {
      tLastEntryPost = now;
      onCarEntry();
    }
    prevIn = carIn;

    // Front montant sortie → barrière
    if (carOut && !prevOut) onCarExit();
    prevOut = carOut;

    // Log compact
    Serial.print("IR=[");
    for (int i = 0; i < numSpots; i++) Serial.print(occupied[i] ? "1" : "0");
    Serial.printf("] IN=%.1fcm OUT=%.1fcm Occ=%d/%d firstFree=%s\n",
                  dIn, dOut, nOcc, numSpots,
                  backendFirstFreeSpot[0] ? backendFirstFreeSpot : "-");
  }

  // ── B. Sync backend chaque 1 seconde ou si changement IR ─
  bool changed = false;
  for (int i = 0; i < numSpots; i++) {
    if (occupied[i] != occSent[i]) { changed = true; break; }
  }

  if (firstSync || changed || (now - tSync >= SYNC_MS)) {
    if (ensureWifi()) {
      syncWithBackend();
      firstSync = false;
      tSync = now;
    }
  }

  // ── C. LCD ──────────────────────────────────────────────
  if (now - tLcd >= LCD_MS) {
    tLcd = now;
    renderLcd(countOccupied(), numSpots - countOccupied());
  }

  // ── D. Fermeture auto des barrières ─────────────────────
  tickGates();

  yield();
}
