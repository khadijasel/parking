#ifndef PARKING_STATE_H
#define PARKING_STATE_H

#include "../config/config.h"

// ════════════════════════════════════════════════════════════
//  État global du parking
//
//  Chaque place a 3 états possibles :
//    LIBRE    → IR HIGH, LED jaune éteinte
//    OCCUPE   → IR LOW,  LED jaune éteinte
//    RESERVE  → IR HIGH (encore libre physiquement),
//               LED jaune ALLUMÉE  ← info vient de l'API
// ════════════════════════════════════════════════════════════

enum SpotStatus { LIBRE = 0, OCCUPE = 1, RESERVE = 2 };

struct Spot {
  const char* label;       // "A1" .. "B3"
  uint8_t     irPin;       // pin capteur IR
  uint8_t     ledPin;      // pin LED jaune
  SpotStatus  status;      // état courant
  SpotStatus  sentStatus;  // dernier état envoyé à l'API
  bool        changed;     // indique si un envoi API est nécessaire
};

struct ParkingState {
  Spot          spots[NB_PLACES];
  int           freeCnt;           // nombre de places libres
  bool          gateInOpen;        // barrière entrée ouverte
  bool          gateOutOpen;       // barrière sortie ouverte
  bool          carAtEntry;        // voiture détectée entrée
  bool          carAtExit;         // voiture détectée sortie
  bool          wifiOk;
  bool          hasSession;
  char          sessionId[64];
};

// ── Labels et pins ────────────────────────────────────────────
static const char*   LABELS[NB_PLACES]   = {"A01","P02","P03","P04","P05","P06"};
static const uint8_t IR_PINS[NB_PLACES]  = {IR_A1,IR_A2,IR_A3,IR_B1,IR_B2,IR_B3};
static const uint8_t LED_PINS[NB_PLACES] = {LED_A1,LED_A2,LED_A3,LED_B1,LED_B2,LED_B3};

// ── Initialisation ────────────────────────────────────────────
inline void initState(ParkingState& s) {
  for (int i = 0; i < NB_PLACES; i++) {
    s.spots[i] = {
      LABELS[i], IR_PINS[i], LED_PINS[i],
      LIBRE, LIBRE, false
    };
  }
  s.freeCnt    = NB_PLACES;
  s.gateInOpen = s.gateOutOpen = false;
  s.carAtEntry = s.carAtExit   = false;
  s.wifiOk     = s.hasSession  = false;
  memset(s.sessionId, 0, sizeof(s.sessionId));
}

// ── Helpers ───────────────────────────────────────────────────
inline int countFree(const ParkingState& s) {
  int n = 0;
  for (int i = 0; i < NB_PLACES; i++)
    if (s.spots[i].status == LIBRE) n++;
  return n;
}

inline int firstFree(const ParkingState& s) {
  for (int i = 0; i < NB_PLACES; i++)
    if (s.spots[i].status == LIBRE) return i;
  return -1;
}

#endif
