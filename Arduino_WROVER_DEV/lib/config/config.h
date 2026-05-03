#ifndef CONFIG_H
#define CONFIG_H

// ════════════════════════════════════════════════════════════
//  SmartPark — ESP32 WROVER-Dev
//  Matériel final :
//    • 1× LCD 16×2 I2C (adresse 0x27)
//    • 6× LED jaune (1 par place, allumée = RÉSERVÉ)
//    • 6× Capteur IR FC-51 (détection occupation)
//    • 2× HC-SR04 (entrée + sortie)
//    • 2× Servo SG90 (barrière entrée + sortie)
//    • ESP32 WROVER-Dev
//
//  RÈGLES WROVER — pins interdits :
//    ✗ GPIO 6-11  → Flash interne
//    ✗ GPIO 16-17 → PSRAM
//    ✗ GPIO 34-39 → INPUT ONLY (pas de sortie)
// ════════════════════════════════════════════════════════════

// ── WiFi ─────────────────────────────────────────────────────
#define WIFI_SSID        "idoomAdsl"
#define WIFI_PASSWORD    "afafimad1967"
#define WIFI_TIMEOUT_MS  15000

// ── API Laravel ───────────────────────────────────────────────
#define API_BASE_URL     "http://192.168.1.3:8000/api"
#define IOT_SECRET_KEY   "smartpark_iot_secret_key_2024"
#define PARKING_ID       "arduino-sim"
#define API_TIMEOUT_MS   8000

// ════════════════════════════════════════════════════════════
//  BROCHES — Attribution définitive WROVER-Dev
// ════════════════════════════════════════════════════════════

// ── HC-SR04 Ultrason ─────────────────────────────────────────
//  ⚠️  ECHO = 5V → pont diviseur 1kΩ/2kΩ obligatoire vers 3.3V
#define TRIG_ENTREE      4    // ✓
#define ECHO_ENTREE      5    // ✓  (avec diviseur)
#define TRIG_SORTIE      18   // ✓
#define ECHO_SORTIE      19   // ✓  (avec diviseur)
#define DISTANCE_SEUIL   18   // cm — voiture détectée si < 18 cm

// ── Servomoteurs SG90 ─────────────────────────────────────────
//  Alimenter depuis 5V externe — jamais depuis ESP32
#define SERVO_ENTREE     13   // ✓  signal PWM
#define SERVO_SORTIE     14   // ✓  signal PWM
#define SERVO_FERME      10   // degrés  → barrière bloquée
#define SERVO_OUVERT     90   // degrés  → voie libre
#define SERVO_DUREE_MS   3500 // ms avant fermeture automatique

// ── Capteurs IR FC-51 ─────────────────────────────────────────
//  LOW  = voiture présente (OCCUPÉ)
//  HIGH = rien devant      (LIBRE)
#define IR_A1   25   // ✓
#define IR_A2   26   // ✓
#define IR_A3   27   // ✓
#define IR_B1   32   // ✓
#define IR_B2   33   // ✓
#define IR_B3   15   // ✓  (légèrement actif au boot — ignorable)

// ── LEDs jaunes — 1 par place, allumée = RÉSERVÉ ─────────────
//  Câblage : anode(+) → résistance 220Ω → GPIO
//            cathode(−) → GND
//  Éteinte  = libre ou occupée (capteur IR s'en charge)
//  Allumée  = place réservée via l'application mobile
#define LED_A1   21   // ✓
#define LED_A2   22   // ✓
#define LED_A3   23   // ✓
#define LED_B1    2   // ✓  (LED onboard aussi — OK)
#define LED_B2    0   // ✓  (boot pin — pull-up 10kΩ conseillée)
#define LED_B3   12   // ✓  (pull-down 10kΩ conseillée)

// ── LCD 16×2 I2C ─────────────────────────────────────────────
//  Module I2C PCF8574 — adresse 0x27
//  VCC → 5V externe · GND → GND commun
//  SDA / SCL → 3.3V OK
#define LCD_SDA   21   // ← Note : partagé avec LED_A1
#define LCD_SCL   22   // ← Note : partagé avec LED_A2
//  Solution : le bus I2C est open-drain, la LED peut cohabiter
//  si on l'utilise en sortie SEULEMENT quand le bus est libre
//  → Utiliser GPIO différents si problème (voir README)
#define LCD_ADDR  0x27
#define LCD_COLS  16
#define LCD_ROWS  2

// ── Timings ───────────────────────────────────────────────────
#define POLL_MS      2000   // lecture IR + HC-SR04
#define API_MS       6000   // sync avec Laravel
#define LCD_MS       1500   // rafraîchissement écran

// ── Parking ───────────────────────────────────────────────────
#define NB_PLACES    6

// ── Debug ─────────────────────────────────────────────────────
#define BAUD_RATE    115200
#define DEBUG        true

#endif
