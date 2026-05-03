#ifndef API_CLIENT_H
#define API_CLIENT_H

#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include "../config/config.h"
#include "../parking/parking_state.h"

// ════════════════════════════════════════════════════════════
//  Client HTTP → Laravel API
//  ESP32 WROVER-Dev
//
//  Endpoints IoT utilisés :
//    POST /api/iot/spot-update      → état d'une place
//    POST /api/iot/session/start    → voiture entrée
//    POST /api/iot/session/{id}/end → voiture sortie
//    GET  /api/iot/spots/status     → sync réservations app
//
//  Header requis sur chaque requête : X-IoT-Key
// ════════════════════════════════════════════════════════════

class ApiClient {
public:

  // ── WiFi ───────────────────────────────────────────────────
  bool connectWifi() {
    if (DEBUG) Serial.printf("[WIFI] Connexion à '%s'", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    unsigned long t = millis();
    while (WiFi.status() != WL_CONNECTED) {
      if (millis() - t > WIFI_TIMEOUT_MS) {
        if (DEBUG) Serial.println("\n[WIFI] Timeout — mode hors ligne");
        return false;
      }
      delay(500);
      if (DEBUG) Serial.print(".");
    }
    if (DEBUG) Serial.printf("\n[WIFI] OK  IP: %s\n",
      WiFi.localIP().toString().c_str());
    return true;
  }

  bool isUp() const { return WiFi.status() == WL_CONNECTED; }
  String ip()  const { return WiFi.localIP().toString(); }

  // ── POST /api/iot/spot-update ──────────────────────────────
  bool updateSpot(const char* label, SpotStatus s) {
    if (!isUp()) return false;
    StaticJsonDocument<128> doc;
    doc["parking_id"] = PARKING_ID;
    doc["spot_label"] = label;
    doc["status"]     = (s == OCCUPE)  ? "occupied" :
                        (s == RESERVE) ? "reserved" : "free";
    bool ok = _post("/iot/spot-update", doc);
    if (DEBUG)
      Serial.printf("[API] spot-update %s=%s %s\n",
        label,
        s == OCCUPE ? "occupied" : s == RESERVE ? "reserved" : "free",
        ok ? "OK" : "ERR");
    return ok;
  }

  // ── POST /api/iot/session/start ────────────────────────────
  String startSession() {
    if (!isUp()) return "";
    StaticJsonDocument<96> doc;
    doc["parking_id"] = PARKING_ID;
    String res = _postResp("/iot/session/start", doc);
    if (res.isEmpty()) return "";
    DynamicJsonDocument j(256);
    if (deserializeJson(j, res) || !j["success"]) return "";
    String sid = j["session_id"].as<String>();
    if (DEBUG) Serial.printf("[API] session/start → %s\n", sid.c_str());
    return sid;
  }

  // ── POST /api/iot/session/{id}/end ─────────────────────────
  bool endSession(const char* sid) {
    if (!isUp() || !sid || !*sid) return false;
    String path = String("/iot/session/") + sid + "/end";
    StaticJsonDocument<32> doc;
    bool ok = _post(path.c_str(), doc);
    if (DEBUG) Serial.printf("[API] session/end → %s\n", ok ? "OK" : "ERR");
    return ok;
  }

  // ── GET /api/iot/spots/status ──────────────────────────────
  // Synchronise les réservations créées depuis l'app mobile
  // Met à jour uniquement les places encore LIBRES physiquement
  bool syncReservations(ParkingState& st) {
    if (!isUp()) return false;
    HTTPClient http;
    String url = String(API_BASE_URL)
               + "/iot/spots/status?parking_id=" + PARKING_ID;
    http.begin(url);
    http.addHeader("X-IoT-Key", IOT_SECRET_KEY);
    http.setTimeout(API_TIMEOUT_MS);
    int code = http.GET();
    if (code != 200) { http.end(); return false; }
    String body = http.getString();
    http.end();

    DynamicJsonDocument doc(1024); // WROVER 4MB PSRAM → OK
    if (deserializeJson(doc, body)) return false;

    for (JsonObject s : doc["spots"].as<JsonArray>()) {
      const char* lbl = s["label"];
      const char* sts = s["status"];
      for (int i = 0; i < NB_PLACES; i++) {
        if (strcmp(st.spots[i].label, lbl) == 0) {
          if (strcmp(sts, "reserved") == 0
              && st.spots[i].status == LIBRE) {
            st.spots[i].status  = RESERVE;
            st.spots[i].changed = true;
            if (DEBUG)
              Serial.printf("[API] %s → RESERVE (app)\n", lbl);
          }
          // Si la réservation est annulée depuis l'app
          if (strcmp(sts, "free") == 0
              && st.spots[i].status == RESERVE) {
            st.spots[i].status  = LIBRE;
            st.spots[i].changed = true;
            if (DEBUG)
              Serial.printf("[API] %s → LIBRE (annulation)\n", lbl);
          }
          break;
        }
      }
    }
    return true;
  }

  // ── Envoyer l'état complet d'un coup au démarrage ──────────
  bool pushAllSpots(const ParkingState& st) {
    if (!isUp()) return false;
    DynamicJsonDocument doc(512);
    doc["parking_id"] = PARKING_ID;
    JsonArray arr = doc.createNestedArray("spots");
    for (int i = 0; i < NB_PLACES; i++) {
      JsonObject s = arr.createNestedObject();
      s["label"]  = st.spots[i].label;
      s["status"] = (st.spots[i].status == OCCUPE)  ? "occupied" :
                    (st.spots[i].status == RESERVE) ? "reserved" : "free";
    }
    return _post("/iot/spot-update", doc);
  }

private:
  String _base(const char* path) {
    return String(API_BASE_URL) + path;
  }

  void _headers(HTTPClient& h) {
    h.addHeader("Content-Type", "application/json");
    h.addHeader("X-IoT-Key", IOT_SECRET_KEY);
    h.setTimeout(API_TIMEOUT_MS);
  }

  template<typename T>
  bool _post(const char* path, T& doc) {
    HTTPClient http;
    http.begin(_base(path));
    _headers(http);
    String body; serializeJson(doc, body);
    int c = http.POST(body);
    http.end();
    return c == 200 || c == 201;
  }

  template<typename T>
  String _postResp(const char* path, T& doc) {
    HTTPClient http;
    http.begin(_base(path));
    _headers(http);
    String body; serializeJson(doc, body);
    int c = http.POST(body);
    String res = (c == 200 || c == 201) ? http.getString() : "";
    http.end();
    return res;
  }
};

#endif
