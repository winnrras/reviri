"""Unit conversion. Everything is stored in a base unit: g, ml or count."""
from typing import Dict, Optional, Tuple

_ALIASES = {
    "gram": "g", "grams": "g", "kilogram": "kg", "kilograms": "kg",
    "ounce": "oz", "ounces": "oz", "pound": "lb", "pounds": "lb", "lbs": "lb",
    "milliliter": "ml", "millilitre": "ml", "liter": "l", "litre": "l",
    "floz": "fl_oz", "fl oz": "fl_oz", "fluid ounce": "fl_oz",
    "gallon": "gal", "gallons": "gal", "quart": "qt", "quarts": "qt", "pint": "pt", "pints": "pt",
    "teaspoon": "tsp", "tablespoon": "tbsp", "cups": "cup",
    "each": "count", "ea": "count", "pc": "count", "pcs": "count", "piece": "count",
    "pieces": "count", "ct": "count", "unit": "count", "units": "count",
}

# unit -> (base unit, multiplier)
_TO_BASE: Dict[str, Tuple[str, float]] = {
    "g": ("g", 1.0), "kg": ("g", 1000.0), "oz": ("g", 28.3495), "lb": ("g", 453.592),
    "ml": ("ml", 1.0), "l": ("ml", 1000.0), "tsp": ("ml", 4.92892), "tbsp": ("ml", 14.7868),
    "cup": ("ml", 236.588), "fl_oz": ("ml", 29.5735),
    "gal": ("ml", 3785.41), "qt": ("ml", 946.353), "pt": ("ml", 473.176),
    "count": ("count", 1.0),
}

# Only used if someone mixes weight and volume (e.g. "1 cup" of a gram-based item).
DENSITY_G_PER_ML = 1.0


def normalize_unit(unit: str) -> str:
    u = unit.strip().lower().replace(".", "")
    return _ALIASES.get(u, u)


def to_base(qty: float, unit: str, target_base: str, pack_size: Optional[float] = None) -> float:
    """Convert `qty` of `unit` into `target_base` ("g", "ml" or "count").

    Receipts often say "oz" for liquids, so oz becomes fl_oz when the target is ml.
    A bare count of a gram/ml item (e.g. "2 x spinach") means whole packages.
    """
    u = normalize_unit(unit)
    if u == "oz" and target_base == "ml":
        u = "fl_oz"
    if u not in _TO_BASE:
        raise ValueError("unknown unit: %r" % unit)
    base, factor = _TO_BASE[u]
    if base == target_base:
        return qty * factor
    if base == "count" and pack_size:
        return qty * pack_size
    if {base, target_base} == {"g", "ml"}:
        return qty * factor * DENSITY_G_PER_ML
    raise ValueError("cannot convert %r to %s" % (unit, target_base))
