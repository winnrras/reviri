"""Receipt photo -> inventory lots, using the Gemini API.

Gemini only does the reading. It must map every line onto our fixed canonical
ingredient list, and all quantity math afterwards is done by units.py / logic.py.
If GEMINI_API_KEY is not set, the server falls back to a built-in demo receipt.
"""
import base64
from datetime import date
from typing import Any, Dict, List

import catalog
import gemini
import logic
from models import InventoryItem
from units import normalize_unit, to_base

# Receipts count these in store units that hold several of our base units
# (1 garlic bulb = a pack of cloves), so a receipt count means whole packages.
SOLD_BY_PACK = {"garlic"}

PROMPT = """You are reading a photo of a grocery receipt.
Return ONLY a JSON array. One element per FOOD line item:
{"raw": "<line as printed>", "canonical": "<key from the list below or null>", "qty": <number>, "unit": "<g|kg|oz|lb|ml|l|fl_oz|gal|qt|pt|count>", "brand": "<brand or null>", "confidence": <0 to 1>}

Rules:
- Expand abbreviations (e.g. "ORG BNLS CHKN BRST" = organic boneless chicken breast = chicken_breast).
- If the line shows a weight or volume (e.g. "1.5 LB", "16 OZ", "1/2 GAL" = 0.5 gal), use it. Otherwise use unit "count" and the number of items.
- Skip tax, totals, bags, coupons and non-food items (soap, paper towels, etc).
- brand: the full brand name only if the line names one, spelled out (write "Kroger" for "KRO", "Trader Joe's" for "TJ"), else null.
- If a food line matches nothing in the list, set canonical to null.

CANONICAL KEYS: %s
"""


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
        items.append(logic.make_lot(canonical, base_qty, today, row.get("brand")))
    return items


async def parse_receipt(image_bytes: bytes, mime_type: str, today: date) -> List[InventoryItem]:
    if not gemini.has_api_key():
        print("[receipt] GEMINI_API_KEY not set, returning the demo receipt")
        return demo_items(today)
    data = await gemini.generate_json([
        {"text": PROMPT % ", ".join(sorted(catalog.CANON.keys()))},
        {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(image_bytes).decode()}},
    ], "receipt")
    rows = data if isinstance(data, list) else data.get("items", [])
    for row in rows:
        print("[receipt] gemini row:", row)
    return rows_to_items(rows, today)
