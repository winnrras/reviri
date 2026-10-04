"""Canonical ingredient catalog.

Receipts, recipes and inventory all use the keys from data/canonical.json
(e.g. "heavy_cream"), so the math never has to guess what an item is.
Where the numbers come from (details per ingredient in data/SOURCES.md):
- shelf_life_days: USDA FoodKeeper, low end of the range, from the date of purchase.
- price_per_kg: US Bureau of Labor Statistics average prices (Aug 2026) where a series
  exists; the rest are estimates.
- co2e_per_kg: Poore & Nemecek (2018, Science) by food group; foods it doesn't cover fall
  back to the category estimates below.
"""
import json
from pathlib import Path
from typing import Any, Dict

_DATA = Path(__file__).parent / "data"

with open(_DATA / "canonical.json") as _f:
    CANON: Dict[str, Dict[str, Any]] = json.load(_f)

# Anything that spoils within this many days counts as "perishable" (worth rescuing).
PERISHABLE_DAYS = 14

# kg CO2e per kg of food, by category. Fallback ESTIMATES, only for foods without a
# sourced co2e_per_kg in canonical.json (butter, soy sauce, olive oil).
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
    c = CANON[canonical]
    factor = c.get("co2e_per_kg", CO2E_PER_KG.get(c["category"], 2.0))
    return grams_equiv(canonical, qty) / 1000.0 * factor
