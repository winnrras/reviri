"""Receipt photo -> inventory lots, using the Gemini API.

Gemini only does the reading. It must map every line onto our fixed canonical
ingredient list, and all quantity math afterwards is done by units.py / logic.py.
If GEMINI_API_KEY is not set, the server falls back to a built-in demo receipt.
"""
import base64
import json
import os
from datetime import date
from typing import Any, Dict, List

import httpx

import catalog
import logic
from models import InventoryItem
from units import to_base

# Check Google AI Studio for the current model name and override with GEMINI_MODEL if needed.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

PROMPT = """You are reading a photo of a grocery receipt.
Return ONLY a JSON array. One element per FOOD line item:
{"raw": "<line as printed>", "canonical": "<key from the list below or null>", "qty": <number>, "unit": "<g|kg|oz|lb|ml|l|fl_oz|count>", "confidence": <0 to 1>}

Rules:
- Expand abbreviations (e.g. "ORG BNLS CHKN BRST" = organic boneless chicken breast = chicken_breast).
- If the line shows a weight or volume (e.g. "1.5 LB", "16 OZ"), use it. Otherwise use unit "count" and the number of items.
- Skip tax, totals, bags, coupons and non-food items (soap, paper towels, etc).
- If a food line matches nothing in the list, set canonical to null.

CANONICAL KEYS: %s
"""


def has_api_key() -> bool:
    return bool(os.getenv("GEMINI_API_KEY"))


def demo_items(today: date) -> List[InventoryItem]:
    """A fixed receipt for demos and offline development."""
    lines = [
        ("chicken_breast", 680), ("heavy_cream", 473), ("spinach", 283), ("mushrooms", 227),
        ("eggs", 12), ("cheddar", 227), ("onion", 450), ("garlic", 10),
        ("parmesan", 85), ("butter", 227),
    ]
    return [logic.make_lot(c, q, today) for c, q in lines]


def rows_to_items(rows: List[Dict[str, Any]], today: date) -> List[InventoryItem]:
    """Turn Gemini's rows into inventory lots. Unknown or unmatched lines are skipped."""
    items = []
    for row in rows:
        canonical = row.get("canonical")
        if not canonical or not catalog.is_known(canonical):
            print("[receipt] skipped unmatched line:", row.get("raw"))
            continue
        try:
            qty = float(row.get("qty") or 1)
            base_qty = to_base(qty, str(row.get("unit") or "count"),
                               catalog.unit(canonical), catalog.pack_size(canonical))
        except (ValueError, TypeError):
            # Can't understand the amount: assume one standard package.
            base_qty = catalog.pack_size(canonical)
        items.append(logic.make_lot(canonical, base_qty, today))
    return items


def _extract_json(text: str) -> List[Dict[str, Any]]:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    data = json.loads(text)
    return data if isinstance(data, list) else data.get("items", [])


async def parse_receipt(image_bytes: bytes, mime_type: str, today: date) -> List[InventoryItem]:
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        print("[receipt] GEMINI_API_KEY not set, returning the demo receipt")
        return demo_items(today)

    payload = {
        "contents": [{
            "parts": [
                {"text": PROMPT % ", ".join(sorted(catalog.CANON.keys()))},
                {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(image_bytes).decode()}},
            ]
        }],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0},
    }
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(GEMINI_URL % GEMINI_MODEL, json=payload,
                                 headers={"x-goog-api-key": key})
    resp.raise_for_status()
    text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
    return rows_to_items(_extract_json(text), today)
