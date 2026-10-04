"""Fridge photo -> proposed pantry changes, using the Gemini API.

Gemini only says what it sees: which food, how many containers, how full, and the
size printed on the label. Python turns that into amounts (fill level x size) and
compares with the pantry, so a fridge photo UPDATES what we already know about
instead of adding a second carton of milk. Nothing is saved until the user confirms.
"""
import base64
from typing import Any, Dict, List, Optional, Tuple

import catalog
import gemini
import logic
from models import FridgeItem, InventoryItem
from units import to_base

# Main model for fridge photos. None = the default Gemini model (see gemini.py).
FRIDGE_MODEL: Optional[str] = None

# How full a container looks -> fraction of its size.
FILL = {"full": 1.0, "most": 0.75, "half": 0.5, "low": 0.2}
FILL_WORDS = {"full": "full", "most": "mostly full", "half": "about half full", "low": "almost empty"}

PROMPT = """You are looking at a photo of the inside of a fridge.
List the FOOD you can see. Return ONLY a JSON array, one element per kind of food:
{"label": "<what it is, using the printed label when readable, e.g. Fat free skim milk 1 gal>",
 "brand": "<brand printed on the package, e.g. Kikkoman, or null if you can't read one>",
 "canonical": "<key from the list below or null>",
 "how": "container" | "pieces" | "weight",
 "containers": <int, for how=container>,
 "fill": "full" | "most" | "half" | "low",
 "size_qty": <package size>, "size_unit": "<its unit>", "size_printed": <true if read from the label>,
 "pieces": <int, for how=pieces>,
 "grams": <estimated weight, for how=weight>}

Rules:
- Use a key ONLY if it is exactly that food. Similar is not the same:
  canola or vegetable oil is NOT olive_oil, almond or oat milk is NOT milk,
  ketchup or salsa is NOT tomato, sour cream or cream cheese is NOT heavy_cream,
  V8 or a juice blend is NOT apple_juice. When unsure, canonical is null.
- Packaged food: how="container". Judge fill from the liquid line or how much is left.
  Copy the size from the label if you can read it (e.g. 1 gal, 64 fl oz, 32 oz).
  Otherwise estimate the size from how big the container looks (a single yogurt cup is
  about 150 g, a small juice bottle about 450 ml) and set size_printed to false.
- Eggs, lemons, tortillas: how="pieces" with the number you can see.
- Loose produce or unpackaged food (onions, peppers, broccoli): how="weight" with grams.
- Combine identical items into one element. Skip things you cannot identify.
- Skip non-food (cleaning products, medicine).

KEYS (unit): %s
"""


def estimate(row: Dict[str, Any]) -> Tuple[float, str]:
    """Amount in the ingredient's base unit, and a short note on how we got it.
    Raises ValueError if the row can't be turned into an amount."""
    canonical = row["canonical"]
    unit = catalog.unit(canonical)
    pack = catalog.pack_size(canonical)
    how = row.get("how")

    if how == "pieces" and unit == "count":
        n = int(row.get("pieces") or 0)
        if n <= 0:
            raise ValueError("no pieces")
        return float(n), "%d counted" % n

    if how == "weight" and row.get("grams"):
        grams = float(row["grams"])
        if unit == "count":
            per = catalog.info(canonical).get("grams_per_count", 50)
            return float(max(1, round(grams / per))), "about %d g" % grams
        return grams, "about %d g, estimated from the photo" % grams

    # Containers (also the fallback for anything else): fill level x package size.
    containers = max(1, int(row.get("containers") or 1))
    fill = row.get("fill") if row.get("fill") in FILL else "full"
    size, size_note = pack, "a standard pack"
    if row.get("size_qty") and row.get("size_unit"):
        try:
            size = to_base(float(row["size_qty"]), str(row["size_unit"]), unit, pack)
            size_note = "%s %s" % (_num(row["size_qty"]), row["size_unit"])
            if row.get("size_printed") is False:
                size_note = "about " + size_note
        except (ValueError, TypeError):
            pass
    qty = containers * size * FILL[fill]
    if unit == "count":
        qty = float(max(1, round(qty)))
    note = "%d x %s, %s" % (containers, size_note, FILL_WORDS[fill]) if containers > 1 \
        else "%s, %s" % (size_note, FILL_WORDS[fill])
    return qty, note


def _num(x: Any) -> str:
    f = float(x)
    return str(int(f)) if f == int(f) else str(f)


def to_proposals(rows: List[Dict[str, Any]], inventory: List[InventoryItem]) -> List[FridgeItem]:
    """Compare what Gemini saw with the pantry: update, add, or not tracked."""
    tracked: Dict[str, List[Tuple[str, float, str]]] = {}
    brands: Dict[str, str] = {}
    untracked: List[FridgeItem] = []
    for row in rows:
        label = str(row.get("label") or "").strip()
        canonical = row.get("canonical")
        if canonical and catalog.is_known(canonical):
            try:
                qty, note = estimate(row)
                tracked.setdefault(canonical, []).append((label, qty, note))
                brand = logic.clean_brand(row.get("brand"))
                if brand and canonical not in brands:
                    brands[canonical] = brand
                continue
            except (ValueError, TypeError):
                pass
        if label:
            untracked.append(FridgeItem(label=label, canonical=None, display_name=label, qty_base=0,
                                        unit_base="", action="untracked", pantry_qty=0, estimate=""))

    have: Dict[str, float] = {}
    for lot in inventory:
        have[lot.canonical] = have.get(lot.canonical, 0.0) + lot.qty_base

    out = []
    for canonical, seen in tracked.items():
        in_pantry = round(have.get(canonical, 0.0), 1)
        out.append(FridgeItem(
            label=" + ".join(s[0] for s in seen if s[0]) or catalog.display(canonical),
            canonical=canonical,
            display_name=catalog.display(canonical),
            qty_base=round(sum(s[1] for s in seen), 1),
            unit_base=catalog.unit(canonical),
            action="update" if in_pantry > 0 else "add",
            pantry_qty=in_pantry,
            estimate="; ".join(s[2] for s in seen),
            brand=brands.get(canonical),
        ))
    out.sort(key=lambda i: (i.action != "update", i.display_name))
    return out + sorted(untracked, key=lambda i: i.label)


async def scan(image_bytes: bytes, mime_type: str, inventory: List[InventoryItem]) -> List[FridgeItem]:
    keys = ", ".join("%s (%s)" % (k, v["unit"]) for k, v in sorted(catalog.CANON.items()))
    data = await gemini.generate_json([
        {"text": PROMPT % keys},
        {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(image_bytes).decode()}},
    ], "fridge", model=FRIDGE_MODEL)
    rows = data if isinstance(data, list) else data.get("items", [])
    for row in rows:
        print("[fridge] gemini row:", row)
    return to_proposals([r for r in rows if isinstance(r, dict)], inventory)
