#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "../config/config.h"
#include "../parking/parking_state.h"

// ════════════════════════════════════════════════════════════
//  LCD 16×2 I2C — adresse 0x27
//  1 seul écran placé à l'entrée
//
//  Branchement :
//    VCC → 5V externe
//    GND → GND commun
//    SDA → GPIO21  (WROVER : Wire.begin(21,22) explicite)
//    SCL → GPIO22
//
//  Note WROVER : Wire.begin() sans paramètres = GPIO21/22
//  On l'appelle explicitement pour être sûr.
//
//  Alternance automatique des messages :
//    3s → infos entrée  (places disponibles + état)
//    3s → infos sortie  (message selon état barrière)
// ════════════════════════════════════════════════════════════

class DisplayManager {
  LiquidCrystal_I2C _lcd;
  bool              _ok;
  bool              _showExit;   // true = affiche message sortie
  unsigned long     _lastSwap;
  static const int  SWAP_MS = 3000;

  // Caractères personnalisés
  byte _charLock[8] = {
    0b01110, 0b10001, 0b10001, 0b11111,
    0b11011, 0b11011, 0b11111, 0b00000
  };
  byte _charCar[8] = {
    0b00000, 0b01110, 0b11111, 0b11111,
    0b11111, 0b01010, 0b00000, 0b00000
  };

public:
  DisplayManager()
    : _lcd(LCD_ADDR, LCD_COLS, LCD_ROWS),
      _ok(false), _showExit(false), _lastSwap(0) {}

  void begin() {
    // WROVER : spécifier SDA/SCL explicitement
    Wire.begin(LCD_SDA, LCD_SCL);
    _lcd.init();
    _lcd.backlight();
    _lcd.createChar(0, _charLock);
    _lcd.createChar(1, _charCar);
    _ok = true;
    _splash();
    if (DEBUG) Serial.println("[LCD] 0x27 OK (SDA=GPIO21 SCL=GPIO22)");
  }

  // Appeler dans loop() — alterne messages entrée/sortie
  void tick(const ParkingState& st) {
    if (!_ok) return;
    unsigned long now = millis();
    if (now - _lastSwap >= SWAP_MS) {
      _showExit = !_showExit;
      _lastSwap = now;
      _showExit ? _renderExit(st) : _renderEntry(st);
    }
  }

  // Message personnalisé (2 lignes max 16 chars)
  void msg(const char* l1, const char* l2 = "                ") {
    if (!_ok) return;
    _lcd.clear();
    _lcd.setCursor(0, 0); _lcd.print(l1);
    _lcd.setCursor(0, 1); _lcd.print(l2);
  }

  void showFull() {
    msg("PARKING COMPLET ", " Revenez + tard ");
  }

  void showWifiWait() {
    msg("  WiFi...       ", "  Connexion     ");
  }

  void showWifiOk(const String& ip) {
    _lcd.clear();
    _lcd.setCursor(0, 0); _lcd.print("WiFi connecte ! ");
    _lcd.setCursor(0, 1);
    String s = ip.length() > 16 ? ip.substring(0, 16) : ip;
    _lcd.print(s);
    delay(1800);
  }

  void showWifiErr() {
    msg("WiFi ERREUR     ", "Mode hors-ligne ");
  }

private:
  // ── Affichage côté ENTRÉE ─────────────────────────────────
  void _renderEntry(const ParkingState& st) {
    _lcd.clear();

    // Ligne 0 : "ENTREE  x/6 lib."
    _lcd.setCursor(0, 0);
    char l0[17];
    snprintf(l0, sizeof(l0), "ENTREE  %d/6 lib.", st.freeCnt);
    _lcd.print(l0);

    // Ligne 1 : état de chaque place (L=libre O=occupé R=réservé)
    // ex : "A1:L A2:O B1:R B2:L"  — tronqué à 16 chars
    _lcd.setCursor(0, 1);
    char l1[17] = "";
    // Format compact : A1L A2O A3L B1R B2L B3L
    for (int i = 0; i < NB_PLACES; i++) {
      char c = (st.spots[i].status == LIBRE)  ? 'L' :
               (st.spots[i].status == OCCUPE) ? 'O' : 'R';
      char seg[4];
      snprintf(seg, sizeof(seg), "%s%c", (i == 3 ? " " : ""), c);
      if (i < 3) {
        strncat(l1, st.spots[i].label, 2);
        strncat(l1, &c, 1);
        if (i < 2) strncat(l1, " ", 1);
      } else {
        if (i == 3) strncat(l1, " | ", 3);
        strncat(l1, st.spots[i].label, 2);
        strncat(l1, &c, 1);
        if (i < 5) strncat(l1, " ", 1);
      }
    }
    _lcd.print(l1);
  }

  // ── Affichage côté SORTIE ─────────────────────────────────
  void _renderExit(const ParkingState& st) {
    _lcd.clear();
    _lcd.setCursor(0, 0);

    if (st.gateOutOpen) {
      _lcd.print("SORTIE : Ouverte");
      _lcd.setCursor(0, 1);
      _lcd.print(" Bonne route !  ");
    } else if (st.hasSession) {
      _lcd.print("SORTIE : Scannez");
      _lcd.setCursor(0, 1);
      _lcd.print(" votre QR code  ");
    } else {
      _lcd.print("SORTIE : Fermee ");
      _lcd.setCursor(0, 1);
      char l1[17];
      snprintf(l1, sizeof(l1), " Places : %d/6   ", st.freeCnt);
      _lcd.print(l1);
    }
  }

  void _splash() {
    _lcd.clear();
    _lcd.setCursor(3, 0); _lcd.print("SmartPark");
    _lcd.setCursor(1, 1); _lcd.print("Initialisation");
    delay(1400);
    _lcd.clear();
  }
};

#endif
