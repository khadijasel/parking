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
//  Endpoint capteurs utilisé :
//    POST /api/parkings/infrared/readings → états des 6 capteurs IR
//
//  Header requis sur chaque requête : X-Sensor-Key
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

  // ── POST /api/parkings/infrared/readings ───────────────────
  bool sendInfraredReadings(const ParkingState& st) {
    if (!isUp()) return false;
    DynamicJsonDocument doc(768);
    doc["parking_id"] = PARKING_ID;
    doc["device_id"] = "ESP32-WROVER-DEV";
    JsonArray arr = doc.createNestedArray("readings");
    for (int i = 0; i < NB_PLACES; i++) {
      JsonObject s = arr.createNestedObject();
      s["spot_label"] = st.spots[i].label;
      s["occupied"] = (st.spots[i].status == OCCUPE);
    }
    bool ok = _post("/parkings/infrared/readings", doc);
    if (DEBUG) {
      Serial.printf("[API] infrared/readings (%d spots) %s\n", NB_PLACES, ok ? "OK" : "ERR");
    }
    return ok;
  }

private:
  String _base(const char* path) {
    return String(API_BASE_URL) + path;
  }

  void _headers(HTTPClient& h) {
    h.addHeader("Content-Type", "application/json");
    h.addHeader("X-Sensor-Key", IOT_SECRET_KEY);
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
