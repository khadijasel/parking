#ifndef IR_SENSOR_H
#define IR_SENSOR_H

#include <Arduino.h>
#include "../config/config.h"
#include "../parking/parking_state.h"

// ════════════════════════════════════════════════════════════
//  Capteurs IR FC-51  — 6 places
//
//  Branchement par capteur :
//    VCC → 3.3V ESP32
//    GND → GND commun
//    OUT → GPIO correspondant
//
//  Réglage potentiomètre bleu sur le module :
//    Tourner jusqu'à ce que la LED rouge s'allume
//    quand RIEN n'est devant, et s'éteigne quand
//    la voiture est là.
// ════════════════════════════════════════════════════════════

class IrManager {
  static const uint16_t DEBOUNCE = 400; // ms
  unsigned long _last[NB_PLACES];

public:
  void begin() {
    for (int i = 0; i < NB_PLACES; i++) {
      pinMode(IR_PINS[i], INPUT);
      _last[i] = 0;
    }
    if (DEBUG) Serial.println("[IR] 6 capteurs OK");
  }

  // Retourne true si au moins une place a changé
  bool update(ParkingState& st) {
    bool any = false;
    unsigned long now = millis();

    for (int i = 0; i < NB_PLACES; i++) {
      if (now - _last[i] < DEBOUNCE) continue;  // anti-rebond

      int raw = digitalRead(st.spots[i].irPin);
      // LOW = objet détecté = voiture = OCCUPÉ
      SpotStatus det = (raw == LOW) ? OCCUPE : LIBRE;

      // Ne pas écraser RESERVE si la place est encore vide physiquement
      if (st.spots[i].status == RESERVE && det == LIBRE) continue;

      if (det != st.spots[i].status) {
        if (DEBUG)
          Serial.printf("[IR] %s  %s → %s\n",
            st.spots[i].label,
            st.spots[i].status == OCCUPE  ? "OCC" :
            st.spots[i].status == RESERVE ? "RES" : "LIB",
            det == OCCUPE ? "OCC" : "LIB");

        st.spots[i].status  = det;
        st.spots[i].changed = true;
        _last[i] = now;
        any = true;
      }
    }
    st.freeCnt = countFree(st);
    return any;
  }
};

#endif
