"""Receipt photo -> inventory lots, using the Gemini API.

Gemini only does the reading. It must map every line onto our fixed canonical
ingredient list, and all quantity math afterwards is done by units.py / logic.py.
If GEMINI_API_KEY is not set, the server falls back to a built-in demo receipt.
"""
import asyncio
import base64
import json
import os
from datetime import date
from typing import Any, Dict, List

import httpx

import catalog
import logic
from models import InventoryItem
from units import normalize_unit, to_base

# Receipts count these in store units that hold several of our base units
# (1 garlic bulb = a pack of cloves), so a receipt count means whole packages.
SOLD_BY_PACK = {"garlic"}

# Check Google AI Studio for the current model name and override with GEMINI_MODEL if needed.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
# Tried in order when the main model is overloaded (503) or rate limited (429).
GEMINI_FALLBACK_MODELS = os.getenv(
    "GEMINI_FALLBACK_MODELS", "gemini-3.5-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite").split(",")
RETRY_STATUSES = {429, 500, 503}
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
GEMINI_LIST_URL = "https://generativelanguage.googleapis.com/v1beta/models"

PROMPT = """You are reading a photo of a grocery receipt.
Return ONLY a JSON array. One element per FOOD line item:
{"raw": "<line as printed>", "canonical": "<key from the list below or null>", "qty": <number>, "unit": "<g|kg|oz|lb|ml|l|fl_oz|gal|qt|pt|count>", "confidence": <0 to 1>}

Rules:
- Expand abbreviations (e.g. "ORG BNLS CHKN BRST" = organic boneless chicken breast = chicken_breast).
- If the line shows a weight or volume (e.g. "1.5 LB", "16 OZ", "1/2 GAL" = 0.5 gal), use it. Otherwise use unit "count" and the number of items.
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
            unit = str(row.get("unit") or "count")
            if canonical in SOLD_BY_PACK and normalize_unit(unit) == "count":
                base_qty = qty * catalog.pack_size(canonical)
            else:
                base_qty = to_base(qty, unit, catalog.unit(canonical), catalog.pack_size(canonical))
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
    headers = {"x-goog-api-key": key}
    async with httpx.AsyncClient(timeout=60) as client:
        # Main model, one retry after a short wait, then each fallback model.
        attempts = [(GEMINI_MODEL, 0), (GEMINI_MODEL, 2)] + [(m.strip(), 0) for m in GEMINI_FALLBACK_MODELS]
        for model, wait in attempts:
            await asyncio.sleep(wait)
            resp = await client.post(GEMINI_URL % model, json=payload, headers=headers)
            if resp.status_code not in RETRY_STATUSES:
                break
            print("[receipt] %s returned %d, trying again" % (model, resp.status_code))
        if resp.status_code == 404:
            # Usually a retired model name: list the ones this key can use.
            models = await client.get(GEMINI_LIST_URL, headers=headers, params={"pageSize": 200})
            names = [m["name"].split("/")[-1] for m in models.json().get("models", [])
                     if "generateContent" in m.get("supportedGenerationMethods", [])]
            raise ValueError("model %r not found (%s). Set GEMINI_MODEL to one of: %s"
                             % (model, resp.text[:300], ", ".join(names)))
    if resp.is_error:
        # Google's error body says why (bad key, quota, image too large...).
        raise ValueError("Gemini returned %d: %s" % (resp.status_code, resp.text[:500]))
    print("[receipt] parsed with", model)
    # Newer models may return "thought" parts before the answer; keep only the answer text.
    parts = resp.json()["candidates"][0]["content"]["parts"]
    text = "".join(p.get("text", "") for p in parts if not p.get("thought"))
    rows = _extract_json(text)
    for row in rows:
        print("[receipt] gemini row:", json.dumps(row))
    return rows_to_items(rows, today)
