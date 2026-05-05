import argparse
import json
import time
from pathlib import Path
from typing import Optional

import serial

from ticket_generator import default_ticket_output_dir, generate_ticket, normalize_base_url


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Arduino serial ticket listener")
    parser.add_argument("--port", required=True, help="Serial port (ex: COM3)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
    parser.add_argument("--api", default="http://localhost:8000/api", help="API base URL")
    parser.add_argument("--parking-id", default="arduino-sim", help="Parking id")
    parser.add_argument("--parking-name", default="Notre Parking", help="Parking name")
    parser.add_argument("--api-key", default=None, help="IoT API key")
    parser.add_argument(
        "--output",
        default=str(default_ticket_output_dir()),
        help="PNG output dir (served by Laravel at /tickets)",
    )
    parser.add_argument("--cooldown", type=int, default=5, help="Seconds to ignore repeated triggers")
    return parser.parse_args()


def is_entry_event(line: str) -> bool:
    text = line.strip()
    if not text:
        return False

    # JSON payload from Arduino
    if text.startswith("{") and text.endswith("}"):
        try:
            payload = json.loads(text)
            event = str(payload.get("event", "")).lower().strip()
            if event in {"entry", "car_in", "vehicle_in", "detect"}:
                return True
        except json.JSONDecodeError:
            return False

    upper = text.upper()
    if upper in {"1", "ENTRY", "CAR_IN", "ENTRY_DETECTED", "ENTREE"}:
        return True

    if "ENTRY" in upper or "CAR" in upper:
        return True

    return False


def main() -> None:
    args = parse_args()
    api_base = normalize_base_url(args.api)
    output_dir = Path(args.output)

    last_trigger_at: Optional[float] = None

    with serial.Serial(args.port, args.baud, timeout=1) as ser:
        print(f"Listening on {args.port} at {args.baud}...")
        while True:
            line_bytes = ser.readline()
            if not line_bytes:
                continue

            try:
                line = line_bytes.decode("utf-8", errors="ignore").strip()
            except UnicodeDecodeError:
                continue

            if not is_entry_event(line):
                continue

            now = time.time()
            if last_trigger_at is not None and now - last_trigger_at < args.cooldown:
                continue

            last_trigger_at = now
            print(f"Entry detected: {line}")

            parking_id = args.parking_id
            parking_name = args.parking_name
            spot_label: Optional[str] = None

            if line.startswith("{") and line.endswith("}"):
                try:
                    payload = json.loads(line)
                    if isinstance(payload, dict):
                        parking_id = str(payload.get("parking_id") or payload.get("parkingId") or parking_id)
                        parking_name = str(payload.get("parking_name") or payload.get("parkingName") or parking_name)
                        raw_spot = payload.get("spot_label") or payload.get("spotLabel")
                        if raw_spot is not None:
                            cleaned = str(raw_spot).strip()
                            spot_label = cleaned or None
                except json.JSONDecodeError:
                    pass

            try:
                result = generate_ticket(
                    api_base_url=api_base,
                    parking_id=parking_id,
                    parking_name=parking_name,
                    output_dir=output_dir,
                    api_key=args.api_key,
                    spot_label=spot_label,
                )
                print(f"Ticket created: {result.ticket.get('id')}")
                print(f"PNG saved: {result.image_path}")
            except Exception as exc:  # pylint: disable=broad-except
                print(f"Ticket generation failed: {exc}")


if __name__ == "__main__":
    main()
