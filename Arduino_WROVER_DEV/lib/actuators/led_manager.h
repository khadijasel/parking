#ifndef LED_MANAGER_H
#define LED_MANAGER_H

#include <Arduino.h>
#include "../config/config.h"
#include "../parking/parking_state.h"

// ════════════════════════════════════════════════════════════
//  6 LEDs jaunes — 1 par place
//
//  Logique simple :
//    LED ALLUMÉE  → place RÉSERVÉE (info vient de l'API)
//    LED ÉTEINTE  → place LIBRE ou OCCUPÉE
//                   (le capteur IR gère l'occupation physique)
//
//  Câblage :
//    Anode (+, patte longue) → résistance 220Ω → GPIO
//    Cathode (−, patte courte) → GND
//
//  Pins utilisées (toutes OUTPUT-capable sur WROVER) :
//    A1=GPIO21  A2=GPIO22  A3=GPIO23
//    B1=GPIO2   B2=GPIO0   B3=GPIO12
// ════════════════════════════════════════════════════════════

class LedManager {
public:
  void begin() {
    for (int i = 0; i < NB_PLACES; i++) {
      pinMode(LED_PINS[i], OUTPUT);
      digitalWrite(LED_PINS[i], LOW);
    }
    _boot_blink();
    if (DEBUG) Serial.println("[LED] 6 LEDs jaunes OK");
  }

  // Met à jour toutes les LEDs selon l'état
  void update(const ParkingState& st) {
    for (int i = 0; i < NB_PLACES; i++) {
      // Allumée uniquement si RÉSERVÉE
      bool on = (st.spots[i].status == RESERVE);
      digitalWrite(st.spots[i].ledPin, on ? HIGH : LOW);
    }
  }

  // Allumer/éteindre une place spécifique
  void set(int idx, bool on) {
    if (idx >= 0 && idx < NB_PLACES)
      digitalWrite(LED_PINS[idx], on ? HIGH : LOW);
  }

  // Éteindre toutes
  void allOff() {
    for (int i = 0; i < NB_PLACES; i++)
      digitalWrite(LED_PINS[i], LOW);
  }

  // Clignotement d'alerte (parking complet)
  void alert(int times = 4, int ms = 120) {
    for (int t = 0; t < times; t++) {
      for (int i = 0; i < NB_PLACES; i++)
        digitalWrite(LED_PINS[i], HIGH);
      delay(ms);
      allOff();
      delay(ms);
    }
  }

private:
  // Séquence de test : allume chaque LED une par une
  void _boot_blink() {
    for (int i = 0; i < NB_PLACES; i++) {
      digitalWrite(LED_PINS[i], HIGH);
      delay(120);
      digitalWrite(LED_PINS[i], LOW);
    }
    delay(80);
  }
};

#endif
