import json
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import qrcode
import requests
from PIL import Image, ImageDraw, ImageFont


@dataclass(frozen=True)
class TicketResult:
    ticket: Dict[str, Any]
    qr_payload: Dict[str, Any]
    image_path: Path


def normalize_base_url(value: str) -> str:
    raw = (value or "").strip()
    if not raw:
        return "http://localhost:8000/api"

    if not re.match(r"^https?://", raw, re.IGNORECASE):
        raw = f"http://{raw}"

    raw = raw.rstrip("/")
    if not raw.endswith("/api"):
        raw = f"{raw}/api"

    return raw


def _sanitize_filename(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_-]+", "_", value.strip())
    return safe.strip("_") or "ticket"


def _algeria_tz() -> timezone:
    return timezone(timedelta(hours=1))


def _default_entry_time_iso() -> str:
    return datetime.now(_algeria_tz()).isoformat()


def _resolve_entry_time(ticket: Dict[str, Any]) -> str:
    entry_time = str(ticket.get("entry_time") or "").strip()
    return entry_time or _default_entry_time_iso()


def _build_qr_payload(ticket: Dict[str, Any], parking_id: str) -> Dict[str, Any]:
    return {
        "ticket_id": str(ticket.get("id") or "").strip(),
        "ticket_code": str(ticket.get("ticket_code") or "").strip(),
        "parking_id": parking_id,
        "entry_time": _resolve_entry_time(ticket),
        "status": str(ticket.get("status") or "unpaid").strip(),
    }


def create_ticket(
    api_base_url: str,
    parking_id: str,
    parking_name: str,
    api_key: Optional[str] = None,
    spot_label: Optional[str] = None,
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    base_url = normalize_base_url(api_base_url)
    url = f"{base_url}/iot/tickets"

    payload = {
        "parking_id": parking_id,
        "parking_name": parking_name,
    }

    if spot_label and str(spot_label).strip():
        payload["spot_label"] = str(spot_label).strip()

    headers = {"Accept": "application/json"}
    if api_key:
        headers["X-IoT-Key"] = api_key

    response = requests.post(url, json=payload, headers=headers, timeout=20)
    if response.status_code not in (200, 201):
        raise RuntimeError(
            f"Ticket API error {response.status_code}: {response.text}"
        )

    data = response.json().get("data") or {}
    ticket = data.get("ticket") or {}
    qr_payload = data.get("qr_payload") or {}
    if not qr_payload:
        qr_payload = _build_qr_payload(ticket, parking_id)

    return ticket, qr_payload


def _make_qr_image(payload: Dict[str, Any], size: int) -> Image.Image:
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=2,
    )
    qr.add_data(json.dumps(payload, ensure_ascii=True))
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    return img.resize((size, size))


def _format_entry_time(entry_iso: str) -> str:
    try:
        dt = datetime.fromisoformat(entry_iso.replace("Z", "+00:00"))
    except ValueError:
        return entry_iso

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)

    dt = dt.astimezone(_algeria_tz())

    return dt.strftime("%Y-%m-%d %H:%M:%S")


def render_ticket_png(
    ticket: Dict[str, Any],
    qr_payload: Dict[str, Any],
    output_dir: Path,
    parking_name_override: Optional[str] = None,
    spot_label_override: Optional[str] = None,
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)

    parking_name = parking_name_override or str(ticket.get("parking_name") or "")
    entry_time = _resolve_entry_time(ticket)
    formatted_entry = _format_entry_time(entry_time)

    width, height = 640, 920
    canvas = Image.new("RGB", (width, height), color="white")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()

    title = "PARKING TICKET"
    draw.text((20, 20), title, fill="black", font=font)

    draw.text((20, 60), f"Parking: {parking_name}", fill="black", font=font)
    draw.text((20, 90), f"Entree: {formatted_entry}", fill="black", font=font)

    spot_label = (spot_label_override or "").strip()
    if not spot_label:
        spot_label = str(ticket.get("spot_label") or ticket.get("spotLabel") or "").strip()
    if spot_label:
        draw.text((20, 150), f"Place: {spot_label}", fill="black", font=font)

    ticket_code = str(ticket.get("ticket_code") or "").strip()
    if ticket_code:
        draw.text((20, 120), f"Code: {ticket_code}", fill="black", font=font)

    qr_size = 360
    qr_image = _make_qr_image(qr_payload, qr_size)
    qr_x = (width - qr_size) // 2
    qr_y = 180
    canvas.paste(qr_image, (qr_x, qr_y))

    ticket_id = str(ticket.get("id") or "")
    suffix = _sanitize_filename(ticket_code or ticket_id)
    filename = f"ticket_{suffix}.png"

    path = output_dir / filename
    canvas.save(path, format="PNG")
    return path


def generate_ticket(
    api_base_url: str,
    parking_id: str,
    parking_name: str,
    output_dir: Path,
    api_key: Optional[str] = None,
    spot_label: Optional[str] = None,
) -> TicketResult:
    ticket, qr_payload = create_ticket(
        api_base_url=api_base_url,
        parking_id=parking_id,
        parking_name=parking_name,
        api_key=api_key,
        spot_label=spot_label,
    )
    image_path = render_ticket_png(
        ticket,
        qr_payload,
        output_dir,
        parking_name,
        spot_label_override=spot_label,
    )
    return TicketResult(ticket=ticket, qr_payload=qr_payload, image_path=image_path)


def default_ticket_output_dir() -> Path:
    repo_root = Path(__file__).resolve().parents[1]
    return repo_root / "parking_back" / "public" / "tickets"


if __name__ == "__main__":
    api_base = normalize_base_url(os.getenv("API_BASE_URL", ""))
    parking_id = os.getenv("PARKING_ID", "arduino-sim")
    parking_name = os.getenv("PARKING_NAME", "Notre Parking")
    api_key = os.getenv("ARDUINO_API_KEY")
    output = Path(os.getenv("TICKET_OUTPUT_DIR", str(default_ticket_output_dir())))

    result = generate_ticket(
        api_base_url=api_base,
        parking_id=parking_id,
        parking_name=parking_name,
        output_dir=output,
        api_key=api_key,
    )

    print(f"Ticket created: {result.ticket.get('id')}")
    print(f"PNG saved: {result.image_path}")
