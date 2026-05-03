# SmartPark — ESP32 WROVER-Dev

## Matériel final
- 1× ESP32 WROVER-Dev
- 1× LCD 16×2 I2C (adresse 0x27)
- 6× LED jaune + 6× résistance 220Ω
- 6× Capteur IR FC-51
- 2× HC-SR04 + 2× R 1kΩ + 2× R 2kΩ (pont diviseur ECHO)
- 2× Servo SG90
- 1× Breadboard + fils + batterie 5V externe

---

## Câblage — tableau complet

### HC-SR04 (×2)
| Broche capteur | Entrée → ESP32 | Sortie → ESP32 |
|---|---|---|
| VCC | 5V batterie ext. | 5V batterie ext. |
| GND | GND commun | GND commun |
| TRIG | GPIO 4 | GPIO 18 |
| ECHO | GPIO 5 ⚠️ | GPIO 19 ⚠️ |

**⚠️ Pont diviseur obligatoire sur ECHO (5V → 3.3V) :**
```
ECHO ──── R1 1kΩ ──┬── GPIO ESP32
                   │
                  R2 2kΩ
                   │
                  GND
```

### Servos SG90 (×2)
| Fil | Entrée | Sortie |
|---|---|---|
| Rouge (VCC) | 5V batterie ext. | 5V batterie ext. |
| Marron (GND) | GND commun | GND commun |
| Orange (Signal) | GPIO 13 | GPIO 14 |

### Capteurs IR FC-51 (×6)
| Place | GPIO | VCC | GND |
|---|---|---|---|
| A1 | 25 | 3.3V | GND commun |
| A2 | 26 | 3.3V | GND commun |
| A3 | 27 | 3.3V | GND commun |
| B1 | 32 | 3.3V | GND commun |
| B2 | 33 | 3.3V | GND commun |
| B3 | 15 | 3.3V | GND commun |

### LEDs jaunes + résistance 220Ω (×6)
| Place | GPIO | Logique |
|---|---|---|
| A1 | 21 | HIGH = réservée |
| A2 | 22 | HIGH = réservée |
| A3 | 23 | HIGH = réservée |
| B1 | 2 | HIGH = réservée |
| B2 | 0 | HIGH = réservée |
| B3 | 12 | HIGH = réservée |

Câblage : **GPIO → résistance 220Ω → anode (+) LED → cathode (−) → GND**

### LCD 16×2 I2C (0x27)
| LCD | ESP32 |
|---|---|
| VCC | 5V batterie ext. |
| GND | GND commun |
| SDA | GPIO 21 |
| SCL | GPIO 22 |

---

## Arduino IDE — Réglages obligatoires

| Paramètre | Valeur |
|---|---|
| Board | **ESP32 Wrover Module** |
| Partition Scheme | **Huge APP (3MB No OTA)** |
| PSRAM | **Enabled** |
| Upload Speed | 921600 |
| Flash Frequency | 80MHz |

---

## Bibliothèques à installer

`Sketch → Include Library → Manage Libraries`

| Rechercher | Auteur |
|---|---|
| ESP32Servo | Kevin Harrington |
| LiquidCrystal I2C | Frank de Brabander |
| ArduinoJson | Benoit Blanchon (v6) |

---

## config.h — 3 valeurs à changer avant upload

```cpp
#define WIFI_SSID     "ton_wifi"
#define WIFI_PASSWORD "ton_mot_de_passe"
#define API_BASE_URL  "http://192.168.X.X:8000/api"
#define PARKING_ID    "id_mongodb_de_ton_parking"
```

**Trouver ton IP :** Windows → `ipconfig` | Mac/Linux → `ifconfig`

---

## Scanner l'adresse I2C du LCD

Si le LCD ne s'affiche pas :

```cpp
#include <Wire.h>
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  for (byte a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0)
      Serial.printf("LCD trouvé à : 0x%02X\n", a);
  }
}
void loop() {}
```

---

## Pins WROVER-Dev — rappel interdits

| GPIO | Pourquoi interdit |
|---|---|
| 6, 7, 8, 9, 10, 11 | Flash SPI interne |
| 16, 17 | PSRAM du module |
| 34, 35, 36, 39 | INPUT ONLY — pas de sortie |
