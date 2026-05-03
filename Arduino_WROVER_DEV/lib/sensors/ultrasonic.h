#ifndef ULTRASONIC_H
#define ULTRASONIC_H

#include <Arduino.h>
#include "../config/config.h"

// ════════════════════════════════════════════════════════════
//  HC-SR04 — Détection voiture en entrée / sortie
//
//  ┌──────────────── CÂBLAGE OBLIGATOIRE ────────────────────┐
//  │                                                         │
//  │  HC-SR04 VCC  →  5V externe  (batterie)                 │
//  │  HC-SR04 GND  →  GND commun                             │
//  │  HC-SR04 TRIG →  GPIO direct                            │
//  │                                                         │
//  │  HC-SR04 ECHO →  R1 (1kΩ)  ──┬──  GPIO ESP32 (3.3V)    │
//  │                               │                         │
//  │                             R2 (2kΩ)                    │
//  │                               │                         │
//  │                              GND                        │
//  │                                                         │
//  │  Sans ce pont diviseur → GPIO brûle définitivement !    │
//  └─────────────────────────────────────────────────────────┘
// ════════════════════════════════════════════════════════════

class Ultrasonic {
  uint8_t     _trig, _echo;
  const char* _name;
  bool        _last;
  unsigned long _sinceChange;
  static const uint16_t STABLE_MS = 700;

public:
  Ultrasonic(uint8_t trig, uint8_t echo, const char* name)
    : _trig(trig), _echo(echo), _name(name),
      _last(false), _sinceChange(0) {}

  void begin() {
    pinMode(_trig, OUTPUT);
    pinMode(_echo, INPUT);
    digitalWrite(_trig, LOW);
    if (DEBUG)
      Serial.printf("[HC-SR04] %s  TRIG=GPIO%d  ECHO=GPIO%d\n",
        _name, _trig, _echo);
  }

  float distCm() {
    digitalWrite(_trig, LOW);  delayMicroseconds(2);
    digitalWrite(_trig, HIGH); delayMicroseconds(10);
    digitalWrite(_trig, LOW);
    long t = pulseIn(_echo, HIGH, 25000UL);
    return t ? (t * 0.0343f / 2.0f) : 999.0f;
  }

  // Retourne true si voiture présente (avec confirmation temporelle)
  bool detect() {
    float d   = distCm();
    bool  cur = (d > 0 && d < DISTANCE_SEUIL);
    unsigned long now = millis();

    if (cur != _last) {
      if (_sinceChange == 0) _sinceChange = now;
      else if (now - _sinceChange > STABLE_MS) {
        _last = cur;
        _sinceChange = 0;
        if (DEBUG)
          Serial.printf("[HC-SR04] %s → voiture %s (%.1f cm)\n",
            _name, cur ? "ARRIVEE" : "PARTIE", d);
      }
    } else {
      _sinceChange = 0;
    }
    return _last;
  }
};

#endif
