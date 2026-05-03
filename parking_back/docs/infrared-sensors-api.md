# Infrared Sensors Ingestion API

## Endpoint

- `POST /api/parkings/infrared/readings`

## Security

Set one of the headers below with the configured API key:

- `X-Sensor-Key: <INFRARED_SENSOR_API_KEY>`
- `X-Arduino-Key: <ARDUINO_API_KEY>` (legacy compatibility)

If both keys are empty in backend config, the endpoint accepts requests without key.

## Payload

```json
{
  "parking_id": "arduino-sim",
  "device_id": "ESP32-A1",
  "sent_at": "2026-05-03T09:30:00Z",
  "readings": [
    {
      "spot_id": "R1C1",
      "occupied": true,
      "detected_at": "2026-05-03T09:29:59Z"
    },
    {
      "channel": "D2",
      "occupied": false
    },
    {
      "topic": "parking/pk01/p03",
      "occupied": true
    }
  ]
}
```

Each reading must include at least one identifier:

- `spot_id`, or
- `spot_label`, or
- `channel`, or
- `topic`

`occupied` is required (`true`/`false`, or `1`/`0`).

## Matching Strategy

Backend tries to map each reading to a spot using this order:

1. `spot_id`
2. `spot_label`
3. `topic`
4. `arduino_id` + `channel` (or payload `device_id` + `channel`)
5. unique `channel` alone

## Effect on Data

When a reading is matched:

- spot `state` is set to `OCCUPIED` or `AVAILABLE`
- spot `updatedAt` is refreshed
- parking `available_spots` is recalculated from `indoor_map.spots`
- `parking_availabilities` is synchronized
- `last_sensor_at` is updated

## Example cURL

```bash
curl -X POST "http://localhost:8000/api/parkings/infrared/readings" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-Sensor-Key: your-secret-key" \
  -d '{
    "parking_id": "arduino-sim",
    "device_id": "ESP32-A1",
    "readings": [
      { "channel": "D1", "occupied": 1 },
      { "channel": "D2", "occupied": 0 }
    ]
  }'
```
