#ifndef BARRIER_H
#define BARRIER_H

#include <Arduino.h>
#include <ESP32Servo.h>
#include "../config/config.h"

// ════════════════════════════════════════════════════════════
//  Servomoteur SG90 — Barrière parking
//
//  Branchement :
//    Fil rouge   → 5V batterie externe  (JAMAIS 3.3V ESP32)
//    Fil marron  → GND commun
//    Fil orange  → GPIO signal (3.3V OK)
//
//  Angles :
//    SERVO_FERME  (10°) → barrière bloquée
//    SERVO_OUVERT (90°) → voie libre
//    Fermeture automatique après SERVO_DUREE_MS
// ════════════════════════════════════════════════════════════

class Barrier {
  Servo       _srv;
  uint8_t     _pin;
  const char* _name;
  bool        _open;
  unsigned long _openAt;

public:
  Barrier(uint8_t pin, const char* name)
    : _pin(pin), _name(name), _open(false), _openAt(0) {}

  void begin() {
    _srv.setPeriodHertz(50);
    _srv.attach(_pin, 500, 2500);
    _srv.write(SERVO_FERME);
    delay(500);
    if (DEBUG)
      Serial.printf("[SERVO] %s  GPIO%d  OK\n", _name, _pin);
  }

  void open() {
    if (_open) return;
    _srv.write(SERVO_OUVERT);
    _open  = true;
    _openAt = millis();
    if (DEBUG) Serial.printf("[SERVO] %s  OUVERTE\n", _name);
  }

  void close() {
    _srv.write(SERVO_FERME);
    _open = false;
    if (DEBUG) Serial.printf("[SERVO] %s  FERMÉE\n", _name);
  }

  // Appeler dans loop() — ferme auto après délai
  void tick() {
    if (_open && millis() - _openAt >= SERVO_DUREE_MS)
      close();
  }

  bool isOpen() const { return _open; }

  // Test visuel au démarrage
  void test() {
    _srv.write(SERVO_OUVERT); delay(500);
    _srv.write(SERVO_FERME);  delay(300);
  }
};

#endif
