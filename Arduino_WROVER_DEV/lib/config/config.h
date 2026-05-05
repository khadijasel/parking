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
//    ⚠ GPIO 0      → BOOT pin              — OK après boot
//    ⚠ GPIO 2      → LED onboard           — OK en output
//    ⚠ GPIO 12     → Boot voltage select   — OK après boot
//    ⚠ GPIO 15     → Active UART log boot  — OK
// ════════════════════════════════════════════════════════════

// ── WiFi ─────────────────────────────────────────────────────
#define WIFI_SSID           "TON_WIFI_SSID"
#define WIFI_PASSWORD       "TON_MOT_DE_PASSE"
#define WIFI_TIMEOUT_MS     15000

// ── API Laravel ───────────────────────────────────────────────
#define API_BASE_URL        "http://192.168.1.100:8000/api"
#define IOT_SECRET_KEY      "smartpark_iot_secret_key_2024"
#define INFRARED_SENSOR_KEY "your_secret_arduino_key_2024"
#define PARKING_ID          "arduino-sim"
#define API_TIMEOUT_MS      8000

// ════════════════════════════════════════════════════════════
//  BROCHES — NOUVEAU CÂBLAGE FINAL
//  (mis à jour selon branchement physique réel)
// ════════════════════════════════════════════════════════════

// ── LEDs jaunes (1 par place, allumée = RÉSERVÉ) ─────────────
//  Câblage : anode(+) → 220Ω → GPIO · cathode(−) → GND
#define LED_P1   23    // Place A1 — ✓ safe
#define LED_P2   27    // Place A2 — ✓ safe
#define LED_P3   15    // Place A3 — ⚠ active UART log au boot (ignorable)
#define LED_P4   12    // Place B1 — ⚠ pull-down 10kΩ conseillée
#define LED_P5    2    // Place B2 — ⚠ LED onboard aussi (cosmétique)
#define LED_P6   -1    // Place B3 — ❌ PIN NON DÉFINIE — trouver GPIO libre
                       //            Candidats libres : GPIO 0, GPIO 4 (si HC-SR04 changé)
                       //            Recommandé : GPIO 0 (avec pull-up 10kΩ)

// ── Aliases (compatibilité) ─────────────────────────────────
// Certains modules utilisent les noms LED_A1..LED_B3.
#define LED_A1 LED_P1
#define LED_A2 LED_P2
#define LED_A3 LED_P3
#define LED_B1 LED_P4
#define LED_B2 LED_P5
#define LED_B3 LED_P6

// ── Capteurs IR FC-51 ─────────────────────────────────────────
//  LOW = voiture présente / HIGH = place libre
//  GPIO 34-39 = INPUT ONLY → parfait pour capteurs
#define IR_A1   34    // Place A1 — ✓ INPUT ONLY (OK pour lecture)
#define IR_A2   35    // Place A2 — ✓ INPUT ONLY
#define IR_A3   32    // Place A3 — ✓ safe
#define IR_B1   33    // Place B1 — ✓ safe
#define IR_B2   25    // Place B2 — ✓ safe
#define IR_B3   26    // Place B3 — ✓ safe

// ── HC-SR04 Ultrason ─────────────────────────────────────────
//  ⚠️ PONT DIVISEUR OBLIGATOIRE SUR ECHO (5V → 3.3V) :
//     ECHO → R1(1kΩ) → GPIO → R2(2kΩ) → GND
#define TRIG_ENTREE   4    // ✓ safe
#define ECHO_ENTREE   5    // ✓ safe (avec diviseur tension)
#define TRIG_SORTIE  18    // ✓ safe
#define ECHO_SORTIE  16    // ✓ safe (avec diviseur tension)
                           // Note : GPIO16 est PSRAM sur WROVER !
                           // ⚠️ Si le WROVER utilise la PSRAM → changer
                           //    ECHO_SORTIE vers GPIO 19 ou autre pin libre
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

// ── LCD I2C 16×2 ─────────────────────────────────────────────
//  VCC → 5V externe · GND → GND commun
//  Wire.begin(SDA, SCL) appelé explicitement (WROVER)
#define LCD_SDA   21   // ✓ safe
#define LCD_SCL   22   // ✓ safe
#define LCD_ADDR  0x27 // adresse I2C (0x3F si 0x27 ne marche pas)
#define LCD_COLS  16
#define LCD_ROWS   2

// ════════════════════════════════════════════════════════════
//  RÉSUMÉ CÂBLAGE (pour référence rapide)
//
//  LED_P1  = GPIO 23  (A1)
//  LED_P2  = GPIO 27  (A2)
//  LED_P3  = GPIO 15  (A3)
//  LED_P4  = GPIO 12  (B1)
//  LED_P5  = GPIO 2   (B2)
//  LED_P6  = GPIO ??? (B3) ← À DÉFINIR
//
//  IR_A1   = GPIO 34  (A1) INPUT ONLY
//  IR_A2   = GPIO 35  (A2) INPUT ONLY
//  IR_A3   = GPIO 32  (A3)
//  IR_B1   = GPIO 33  (B1)
//  IR_B2   = GPIO 25  (B2)
//  IR_B3   = GPIO 26  (B3)
//
//  TRIG_E  = GPIO 4   HC-SR04 Entrée
//  ECHO_E  = GPIO 5   HC-SR04 Entrée (+pont diviseur)
//  TRIG_S  = GPIO 18  HC-SR04 Sortie
//  ECHO_S  = GPIO 16  HC-SR04 Sortie (+pont diviseur)
//            ⚠️ GPIO 16 = PSRAM sur WROVER → vérifier !
//
//  SERVO_E = GPIO 13
//  SERVO_S = GPIO 14
//
//  LCD SDA = GPIO 21
//  LCD SCL = GPIO 22
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