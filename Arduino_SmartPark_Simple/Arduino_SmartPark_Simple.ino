#include <Wire.h>

// ════════════════════════════════════════════════════════════
//  SmartPark — ESP32 connecté au backend Laravel
//
//  Câblage :
//    • HC-SR04 ENTREE  : TRIG=GPIO4   ECHO=GPIO5
//    • HC-SR04 SORTIE  : TRIG=GPIO18  ECHO=GPIO19
//    • Servos          : SERVO_IN=13  SERVO_OUT=14
//    • IR x6           : 15, 27, 32, 33, 34, 35  → A1, A2, A3, B1, B2, B3
//    • LEDs (1/place)  : 23, 25, 26, 12, 2, 16   (LED ON = place occupée)
//    • LCD I2C 0x27    : SDA=GPIO21   SCL=GPIO22
//
//  WiFi : SSID="khadija"  Pass="khadija17"
//
//  Endpoints Laravel utilisés :
//    POST /api/parkings/infrared/readings    → état des 6 IR
//    POST /api/parkings/arduino/availability → compteur global
//    POST /api/iot/tickets                   → ticket à l'entrée
//  Header IoT : X-Sensor-Key / X-Arduino-Key / X-IoT-Key
//
//  Bibliothèques :
//    ESP32Servo · LiquidCrystal I2C · ArduinoJson v6
// ════════════════════════════════════════════════════════════

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <Wire.h>
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
#define BARRIER_OPEN_MS 3500   // durée d'ouverture des barrières

// IR (LOW = place occupée) + labels backend
const int   IR_PINS[6]     = {15, 27, 32, 33, 34, 35};
const char* SPOT_LABELS[6] = {"A1", "A2", "A3", "B1", "B2", "B3"};

// LEDs (1 LED par place, ON = occupée)
// ⚠ GPIO 16 = PSRAM sur ESP32 WROVER → mettre -1 si crash au boot
// ⚠ GPIO 12 = strap-pin (HIGH au boot empêche le démarrage) → si crash, mettre -1
const int LED_PINS[6] = {23, 25, 26, 12, 2, -1};   // ⬅ test : GPIO 16 désactivé

// LCD
#define LCD_SDA  21
#define LCD_SCL  22
#define LCD_ADDR 0x27

// WiFi
#define WIFI_SSID       "khadija"
#define WIFI_PASSWORD   "khadija17"
#define WIFI_TIMEOUT_MS 15000

// Backend Laravel — REMPLACER L'IP par celle du PC qui héberge `php artisan serve --host=0.0.0.0`
#define API_BASE_URL    "http://10.133.226.168:8000/api"
#define ARDUINO_API_KEY "smartpark_iot_secret_key_2024"
#define PARKING_ID      "arduino-sim"
#define PARKING_NAME    "Notre Parking"
#define DEVICE_ID       "ESP32-SmartPark"
#define API_TIMEOUT_MS  8000

// Cadences (non-bloquantes)
#define POLL_MS          300
#define SYNC_MS         5000
#define LCD_MS          1000
#define ENTRY_DEBOUNCE  4000
#define WIFI_RETRY_MS  10000

/* ===================== ÉTAT GLOBAL ===================== */

Servo servoIn;
Servo servoOut;
LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);

bool occupied[6] = {false};
bool occSent[6]  = {false};

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
  for (int i = 0; i < 6; i++) if (occupied[i]) n++;
  return n;
}

int firstFreeIndex() {
  for (int i = 0; i < 6; i++) if (!occupied[i]) return i;
  return -1;
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

/* ===================== HTTP ===================== */

int httpPostJson(const char* path, const String& body) {
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
    Serial.printf("[HTTP] %s ERR %s\n", path, http.errorToString(code).c_str());
  } else {
    Serial.printf("[HTTP] %s -> %d\n", path, code);
  }
  http.end();
  return code;
}

bool postInfrared() {
  StaticJsonDocument<768> doc;
  doc["parking_id"] = PARKING_ID;
  doc["device_id"]  = DEVICE_ID;
  JsonArray arr = doc.createNestedArray("readings");
  for (int i = 0; i < 6; i++) {
    JsonObject r = arr.createNestedObject();
    r["spot_label"] = SPOT_LABELS[i];
    r["occupied"]   = occupied[i];
  }
  String body; serializeJson(doc, body);
  int code = httpPostJson("/parkings/infrared/readings", body);
  bool ok = (code == 200 || code == 201);
  if (ok) for (int i = 0; i < 6; i++) occSent[i] = occupied[i];
  return ok;
}

bool postAvailability(int freePlaces) {
  StaticJsonDocument<128> doc;
  doc["available_spots"] = freePlaces;
  doc["total_spots"]     = 6;
  String body; serializeJson(doc, body);
  int code = httpPostJson("/parkings/arduino/availability", body);
  return (code == 200 || code == 201);
}

bool postEntryTicket(const char* spotLabel) {
  StaticJsonDocument<256> doc;
  doc["parking_id"]   = PARKING_ID;
  doc["parking_name"] = PARKING_NAME;
  if (spotLabel && spotLabel[0] != '\0') doc["spot_label"] = spotLabel;
  String body; serializeJson(doc, body);
  int code = httpPostJson("/iot/tickets", body);
  return (code == 200 || code == 201);
}

/* ===================== HARDWARE ===================== */

void readIrSensors() {
  for (int i = 0; i < 6; i++) {
    occupied[i] = (digitalRead(IR_PINS[i]) == LOW);
  }
}

void updateSpotLeds() {
  for (int i = 0; i < 6; i++) {
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
  if (nOccupied >= 6) {
    lcd.print("Parking plein");
  } else {
    lcd.print(nOccupied);
    lcd.print("/6 Lib:");
    lcd.print(nFree);
  }
}

/* ===================== ÉVÉNEMENTS ===================== */

void onCarEntry() {
  int nFree = 6 - countOccupied();
  Serial.printf("[EVENT] Voiture ENTREE  (libre=%d)\n", nFree);

  if (nFree <= 0) {
    Serial.println("[EVENT] Parking COMPLET — refus");
    lcd.setCursor(0, 1);
    lcd.print("Parking COMPLET ");
    return;
  }

  openEntryGate();

  int fi = firstFreeIndex();
  const char* suggested = (fi >= 0) ? SPOT_LABELS[fi] : nullptr;

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

  // LEDs (1 par place) — ignore LED_PINS[i] < 0
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

  // Lecture initiale + premier sync
  readIrSensors();
  updateSpotLeds();
  if (wifiOk) {
    postInfrared();
    postAvailability(6 - countOccupied());
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
    int nFree = 6 - nOcc;

    // Front montant entrée → ticket
    if (carIn && !prevIn && (now - tLastEntryPost > ENTRY_DEBOUNCE)) {
      tLastEntryPost = now;
      onCarEntry();
    }
    prevIn = carIn;

    // Front montant sortie → barrière + log
    if (carOut && !prevOut) onCarExit();
    prevOut = carOut;

    Serial.printf("IR=[%d%d%d%d%d%d] IN=%.1fcm OUT=%.1fcm Occ=%d Lib=%d\n",
                  occupied[0], occupied[1], occupied[2],
                  occupied[3], occupied[4], occupied[5],
                  dIn, dOut, nOcc, nFree);
  }

  // ── B. Sync backend (changement IR ou heartbeat 5 s) ────
  bool changed = false;
  for (int i = 0; i < 6; i++) if (occupied[i] != occSent[i]) { changed = true; break; }

  if (firstSync || changed || (now - tSync >= SYNC_MS)) {
    if (ensureWifi()) {
      postInfrared();
      postAvailability(6 - countOccupied());
      firstSync = false;
      tSync = now;
    }
  }

  // ── C. LCD ──────────────────────────────────────────────
  if (now - tLcd >= LCD_MS) {
    tLcd = now;
    renderLcd(countOccupied(), 6 - countOccupied());
  }

  // ── D. Fermeture auto des barrières ─────────────────────
  tickGates();

  yield();
}
