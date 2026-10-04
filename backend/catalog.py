"""Canonical ingredient catalog.

Receipts, recipes and inventory all use the keys from data/canonical.json
(e.g. "heavy_cream"), so the math never has to guess what an item is.
Shelf lives, prices and CO2e factors below are rough placeholders. Replace them
with sourced numbers (USDA FoodKeeper for shelf life, etc.) before you present.
"""
import json
from pathlib import Path
from typing import Any, Dict

_DATA = Path(__file__).parent / "data"

with open(_DATA / "canonical.json") as _f:
    CANON: Dict[str, Dict[str, Any]] = json.load(_f)

# Anything that spoils within this many days counts as "perishable" (worth rescuing).
PERISHABLE_DAYS = 14

# kg CO2e per kg of food, by category. PLACEHOLDER ballpark values, not sourced.
CO2E_PER_KG = {
    "protein": 7.0,
    "dairy": 4.0,
    "produce": 1.0,
    "eggs": 4.5,
    "grains": 1.5,
    "pantry": 1.5,
    "drinks": 1.0,
}


def is_known(canonical: str) -> bool:
    return canonical in CANON


def info(canonical: str) -> Dict[str, Any]:
    return CANON[canonical]


def display(canonical: str) -> str:
    return CANON[canonical]["display"]


def unit(canonical: str) -> str:
    return CANON[canonical]["unit"]


def pack_size(canonical: str) -> float:
    return float(CANON[canonical]["pack_size"])


def is_perishable(canonical: str) -> bool:
    return CANON[canonical]["shelf_life_days"] <= PERISHABLE_DAYS


def grams_equiv(canonical: str, qty: float) -> float:
    """Approximate weight in grams (ml is treated as 1 g, counts use grams_per_count)."""
    c = CANON[canonical]
    if c["unit"] == "count":
        return qty * c.get("grams_per_count", 50)
    return qty


def price(canonical: str, qty: float) -> float:
    return grams_equiv(canonical, qty) / 1000.0 * CANON[canonical]["price_per_kg"]


def co2e(canonical: str, qty: float) -> float:
    factor = CO2E_PER_KG.get(CANON[canonical]["category"], 2.0)
    return grams_equiv(canonical, qty) / 1000.0 * factor
