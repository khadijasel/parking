# Intégration Arduino ESP32 WROVER ↔ Backend Laravel

## Vue d'ensemble

L'Arduino WROVER envoie les lectures des capteurs infrared au backend Laravel via des requêtes HTTP POST. Le backend traite ces données et met à jour l'état du parking en temps réel.

## Architecture

```
[Arduino ESP32 WROVER]
    ↓ (WiFi)
[6× Capteurs IR]  →  POST /api/parkings/infrared/readings
    ↓
[Backend Laravel]  →  MongoDB
    ↓
[Flutter App]  ←  GET /api/parkings/availability
```

## Endpoints API

### 1. Envoyer les lectures IR

**Endpoint:** `POST /api/parkings/infrared/readings`

**Header requis:**
```
Content-Type: application/json
X-Sensor-Key: <INFRARED_SENSOR_API_KEY>
```

**Payload (exemple):**
```json
{
  "parking_id": "arduino-sim",
  "device_id": "ESP32-WROVER-A1",
  "readings": [
    { "spot_label": "A1", "occupied": true },
    { "spot_label": "A2", "occupied": false },
    { "spot_label": "A3", "occupied": true },
    { "spot_label": "B1", "occupied": false },
    { "spot_label": "B2", "occupied": false },
    { "spot_label": "B3", "occupied": true }
  ]
}
```

**Réponse (succès 200):**
```json
{
  "message": "Infrared sensor readings processed successfully.",
  "data": {
    "parking_id": "arduino-sim",
    "parking_name": "Notre parking",
    "total_spots": 6,
    "available_spots": 3,
    "matched_readings": 6,
    "unmatched_readings": 0,
    "last_sensor_at": "2026-05-03T14:30:00Z",
    "availability": { ... }
  }
}
```

### 2. Récupérer la disponibilité

**Endpoint:** `GET /api/parkings/availability`

**Réponse (exemple):**
```json
{
  "message": "Parking availability retrieved successfully.",
  "data": [
    {
      "parking_id": "arduino-sim",
      "parking_name": "Notre parking",
      "total_spots": 6,
      "available_spots": 3,
      "is_arduino": true,
      "last_sensor_at": "2026-05-03T14:30:00Z"
    }
  ]
}
```

## Configuration

### Backend (.env)

```env
# Dans parking_back/.env
INFRARED_SENSOR_API_KEY=your_secret_arduino_key_2024
ARDUINO_API_KEY=your_secret_arduino_key_2024
```

### Arduino (config.h)

```cpp
// Dans Arduino_WROVER_DEV/lib/config/config.h

// ── WiFi ─────────────────────────
#define WIFI_SSID        "your_wifi_ssid"
#define WIFI_PASSWORD    "your_wifi_password"
#define WIFI_TIMEOUT_MS  15000

#// ── API Backend ──────────────────
#define API_BASE_URL     "http://localhost:8000/api"  // URL du serveur Laravel en dev
#define IOT_SECRET_KEY   "smartpark_iot_secret_key_2024"  // Doit matcher .env
#define PARKING_ID       "arduino-sim"
#define API_TIMEOUT_MS   8000
```

## Cycle de communication

### Au démarrage (setup)

1. Connexion WiFi
2. Lecture initiale des capteurs IR
3. Envoi de l'état complet: `api.pushAllReadings(state)`
4. Sync disponibilité: `api.syncAvailability(state)`

### En boucle (loop - tous les 6 secondes)

1. **taskApi()** s'exécute toutes les `API_MS` millisecondes (6000ms par défaut)
2. Envoie les lectures IR actuelles: `api.sendInfraredReadings(state)`
3. Récupère l'état de disponibilité: `api.syncAvailability(state)`

### Flux des capteurs (tous les 2 secondes)

1. **taskSensors()** s'exécute toutes les `POLL_MS` millisecondes (2000ms par défaut)
2. Lit les 6 capteurs IR → met à jour l'état (OCCUPIED/AVAILABLE)
3. Les changements sont envoyés au prochain cycle taskApi()

## Vérification

### 1. Test en ligne de commande (cURL)

```bash
curl -X POST "http://localhost:8000/api/parkings/infrared/readings" \
  -H "Content-Type: application/json" \
  -H "X-Sensor-Key: your_secret_arduino_key_2024" \
  -d '{
    "parking_id": "arduino-sim",
    "device_id": "ESP32-WROVER-A1",
    "readings": [
      { "spot_label": "A1", "occupied": true },
      { "spot_label": "A2", "occupied": false },
      { "spot_label": "A3", "occupied": true },
      { "spot_label": "B1", "occupied": false },
      { "spot_label": "B2", "occupied": false },
      { "spot_label": "B3", "occupied": true }
    ]
  }'
```

### 2. Vérifier la disponibilité

```bash
curl -X GET "http://localhost:8000/api/parkings/availability" \
  -H "Content-Type: application/json"
```

### 3. Logs Arduino (Serial Monitor 115200)

```
[WIFI] OK  IP: 192.168.1.100
[API] infrared/readings → OK (6 readings)
[API] Parking has 3 available spots
```

## Génération de ticket (Python)

Le dossier `python/` contient un générateur de ticket QR qui appelle l'API Laravel :

- `POST /api/iot/tickets` (header `X-IoT-Key`)
- Génère ensuite une image PNG avec le payload QR.

### 1) Événement série émis par l'ESP32

À chaque détection **d'entrée**, l'ESP32 émet maintenant **une ligne JSON ASCII** sur le port série.
Exemple :

```json
{"event":"entry","parking_id":"arduino-sim","spot_label":"A1"}
```

Le script Python `python/serial_listener.py` écoute ces événements et déclenche la génération du ticket.

Si `spot_label` est présent, le backend l'intègre dans `ticket_code` (ex: `ARD-A1-9F3KQZ`) afin que l'application Flutter puisse déduire la place et lancer le guidage.

### 2) Pré-requis Python

Installer les dépendances :

```bash
pip install -r python/requirements.txt
```

### 3) Lancer le listener

Exemple (Windows) :

```bash
python python/serial_listener.py \
  --port COM3 \
  --api http://<IP_DU_PC>:8000/api \
  --api-key smartpark_iot_secret_key_2024 \
  --parking-id arduino-sim \
  --parking-name "Notre Parking"
```

Notes :
- `--api-key` doit matcher `ARDUINO_API_KEY` côté Laravel.
- L'ESP32 et le PC doivent être sur le même réseau (ou API accessible).

## Timings par défaut

| Opération | Interval | Variable |
|-----------|----------|----------|
| Lecture capteurs IR | 2000ms | `POLL_MS` |
| Sync API | 6000ms | `API_MS` |
| Rafraîchissement LCD | 1500ms | `LCD_MS` |

## Dépannage

### Arduino ne peut pas se connecter au serveur

**Symptômes:** Logs `[WIFI] Reconnexion...` en boucle

**Solution:**
1. Vérifier `API_BASE_URL` dans config.h
2. Vérifier l'IP du serveur Laravel: `ipconfig` (Windows) ou `ifconfig` (Linux)
3. Vérifier que le réseau WiFi est accessible
4. Tester la connectivité: `ping 192.168.1.x`

### Clé API rejetée

**Symptômes:** HTTP 401/403

**Solution:**
1. Vérifier que `IOT_SECRET_KEY` dans config.h == `INFRARED_SENSOR_API_KEY` dans .env backend
2. S'assurer que la clé n'est pas vide dans le config backend

### Aucune matching de readings

**Symptômes:** Erreur 422 "No sensor reading matched a configured parking spot."

**Solution:**
1. Vérifier que les `spot_label` dans le payload correspondent à ["A1", "A2", "A3", "B1", "B2", "B3"]
2. Vérifier que le `parking_id` = "arduino-sim"
3. Vérifier que le parking existe dans MongoDB

## Fichiers modifiés

- `Arduino_WROVER_DEV/lib/network/api_client.h` - Endpoints infrared
- `Arduino_WROVER_DEV/lib/config/config.h` - Configuration API
- `Arduino_WROVER_DEV/SmartPark.ino` - Appels aux nouveaux endpoints
- `parking_back/app/Http/Controllers/Api/ParkingAvailabilityController.php` - Endpoints
- `parking_back/app/Services/Parking/ParkingAvailabilityService.php` - Logique de traitement
- `parking_back/docs/infrared-sensors-api.md` - Documentation

## Prochaines étapes

- [ ] Tester avec l'Arduino physique
- [ ] Configurer les clés API dans .env
- [ ] Monitorer les logs du backend
- [ ] Valider les données dans MongoDB
