#ifndef CONFIG_H
#define CONFIG_H

// ════════════════════════════════════════════════════════════
//  SmartPark — Configuration ESP32 WROVER-Dev
//  Fichier : lib/config/config.h
//
//  RÈGLES WROVER (ne jamais violer) :
//    ✗ GPIO 6-11   → Flash SPI interne     — INTERDITS
//    ✗ GPIO 16-17  → PSRAM du WROVER       — INTERDITS
//    ✗ GPIO 34-39  → INPUT ONLY            — seulement en lecture
//    ⚠ GPIO 0      → BOOT pin              — OK après boot (pull-up 10kΩ)
//    ⚠ GPIO 2      → LED onboard           — OK en output
//    ⚠ GPIO 12     → Boot voltage select   — OK après boot (pull-down conseillée)
//    ⚠ GPIO 15     → Active UART log boot  — OK après boot
// ════════════════════════════════════════════════════════════

// ── WiFi ─────────────────────────────────────────────────────
#define WIFI_SSID           "khadija"
#define WIFI_PASSWORD       "khadija17"
#define WIFI_TIMEOUT_MS     15000

// ── API Laravel ───────────────────────────────────────────────
#define API_BASE_URL        "http://10.133.226.121:8000/api"
#define IOT_SECRET_KEY      "smartpark_iot_secret_key_2024"
#define INFRARED_SENSOR_KEY "your_secret_arduino_key_2024"
#define PARKING_ID          "arduino-sim"
#define API_TIMEOUT_MS      8000

// ════════════════════════════════════════════════════════════
//  BROCHES — CÂBLAGE RÉEL TESTÉ SUR L'ARDUINO IDE
//  (synchronisé avec le code de test validé)
// ════════════════════════════════════════════════════════════

// ── HC-SR04 Ultrason ─────────────────────────────────────────
//  ⚠️ PONT DIVISEUR OBLIGATOIRE SUR ECHO (5V → 3.3V) :
//     ECHO → R1(1kΩ) → GPIO → R2(2kΩ) → GND
//
//  ENTRÉE
#define TRIG_ENTREE   4    // ✓ safe
#define ECHO_ENTREE   5    // ✓ safe (avec pont diviseur)
//  SORTIE — GPIO 19 (et non 16 qui est PSRAM sur WROVER)
#define TRIG_SORTIE  18    // ✓ safe
#define ECHO_SORTIE  19    // ✓ safe (avec pont diviseur)
                           // ⚠️ GPIO 16 INTERDIT sur WROVER (PSRAM) !
#define DISTANCE_SEUIL  18 // cm — voiture détectée si distance < 18 cm

// ── Servomoteurs SG90 ─────────────────────────────────────────
//  Fil rouge   → 5V externe (JAMAIS depuis ESP32)
//  Fil marron  → GND commun
//  Fil orange  → GPIO signal
#define SERVO_ENTREE   13  // ✓ safe PWM
#define SERVO_SORTIE   14  // ✓ safe PWM
#define SERVO_FERME     0  // degrés — barrière bloquée
#define SERVO_OUVERT   90  // degrés — voie libre
#define SERVO_DUREE_MS 3500

// ── Capteurs IR FC-51 ─────────────────────────────────────────
//  LOW = voiture présente / HIGH = place libre
//  Câblage : VCC→3.3V  GND→GND  OUT→GPIO
//
//  Note : GPIO 34 et 35 sont INPUT ONLY → parfait pour capteurs IR
//         GPIO 15 active UART log au boot → ignorable en fonctionnement
#define IR_A1   15    // Place A1 — ⚠ UART log au boot, OK ensuite
#define IR_A2   27    // Place A2 — ✓ safe
#define IR_A3   32    // Place A3 — ✓ safe
#define IR_B1   33    // Place B1 — ✓ safe
#define IR_B2   34    // Place B2 — ✓ INPUT ONLY (OK pour lecture)
#define IR_B3   35    // Place B3 — ✓ INPUT ONLY (OK pour lecture)

// ── LEDs jaunes (1 par place, allumée = RÉSERVÉ) ─────────────
//  Câblage : anode(+) → 220Ω → GPIO · cathode(−) → GND
//
//  Sémantique : LED ALLUMÉE = place RÉSERVÉE (info reçue via API)
//               LED ÉTEINTE = place LIBRE ou OCCUPÉE physiquement
#define LED_P1   23    // Place A1 — ✓ safe
#define LED_P2   25    // Place A2 — ✓ safe
#define LED_P3   26    // Place A3 — ✓ safe
#define LED_P4   12    // Place B1 — ⚠ pull-down 10kΩ conseillée
#define LED_P5    2    // Place B2 — ⚠ LED onboard aussi (cosmétique)
#define LED_P6   16    // Place B3 — ⚠ GPIO 16 câblé physiquement
                       //   IMPORTANT : dans Arduino IDE → Tools → PSRAM → "Disabled"
                       //   Si PSRAM est activée, GPIO 16 entre en conflit → crash WiFi.

// ── Aliases (compatibilité) ─────────────────────────────────
#define LED_A1 LED_P1
#define LED_A2 LED_P2
#define LED_A3 LED_P3
#define LED_B1 LED_P4
#define LED_B2 LED_P5
#define LED_B3 LED_P6

// ── LCD I2C 16×2 ─────────────────────────────────────────────
//  VCC → 5V externe · GND → GND commun
//  Wire.begin(SDA, SCL) appelé explicitement (WROVER)
#define LCD_SDA   21   // ✓ safe
#define LCD_SCL   22   // ✓ safe
#define LCD_ADDR  0x27 // adresse I2C (0x3F si 0x27 ne marche pas)
#define LCD_COLS  16
#define LCD_ROWS   2

// ════════════════════════════════════════════════════════════
//  RÉSUMÉ CÂBLAGE COMPLET (broches testées et validées)
//
//  HC-SR04 Entrée  TRIG = GPIO 4   ECHO = GPIO 5  (+pont diviseur)
//  HC-SR04 Sortie  TRIG = GPIO 18  ECHO = GPIO 19 (+pont diviseur)
//
//  Servo Entrée  = GPIO 13
//  Servo Sortie  = GPIO 14
//
//  IR_A1 = GPIO 15  │  IR_A2 = GPIO 27  │  IR_A3 = GPIO 32
//  IR_B1 = GPIO 33  │  IR_B2 = GPIO 34* │  IR_B3 = GPIO 35*
//                      (* INPUT ONLY)
//
//  LED_A1 = GPIO 23  │  LED_A2 = GPIO 25  │  LED_A3 = GPIO 26
//  LED_B1 = GPIO 12  │  LED_B2 = GPIO 2   │  LED_B3 = GPIO 16 (PSRAM→Disabled!)
//
//  LCD I2C  SDA = GPIO 21  SCL = GPIO 22
//
//  ─── Vérification conflits (20 broches distinctes) ───
//  IR  : 15 27 32 33 34 35  ✓
//  LED : 23 25 26 12  2 16  ✓  (⚠ GPIO 16 → PSRAM doit être Disabled dans IDE)
//  US  :  4  5 18 19         ✓
//  SRV : 13 14               ✓
//  LCD : 21 22               ✓
//  Aucun conflit détecté ✓
// ════════════════════════════════════════════════════════════

// ── Timings ───────────────────────────────────────────────────
#define POLL_MS   2000   // lecture IR + ultrason (ms)
#define API_MS    6000   // sync backend Laravel (ms)
#define LCD_MS    1500   // rafraîchissement LCD (ms)

// ── Parking ───────────────────────────────────────────────────
#define NB_PLACES   6

// ── Debug ─────────────────────────────────────────────────────
#define BAUD_RATE   115200
#define DEBUG       true

#endif // CONFIG_H

