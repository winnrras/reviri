"""Recipe search: the user types a dish name, Gemini writes the recipe.

Gemini writes the recipe and maps each ingredient onto our canonical list.
Python does the unit conversion (units.py), so a generated recipe plugs into the
same pantry math as the built-in recipe book. Ingredients outside the catalog are
kept as plain text ("untracked") and never touch the pantry.
"""
import re
from typing import Any, Dict, List

import catalog
import gemini
from models import IngredientQty, Recipe
from units import normalize_unit, to_base

MAX_NAME_LEN = 80
MAX_SERVINGS = 12

PROMPT = """You write home-cooking recipes for a food-waste app.
The user searched for: "%s"

If that is not a dish or drink someone could cook at home, return {"found": false}.
Otherwise return ONLY this JSON:
{"found": true, "name": "<dish name, title case>", "servings": <int>,
 "ingredients": [{"text": "<as written in a recipe, e.g. 2 cups heavy cream>",
                  "canonical": "<key from the list below or null>",
                  "qty": <number>, "unit": "<unit>"}],
 "steps": ["<short step>", ...]}

Rules:
- A normal, realistic version of the dish. 3 to 10 steps.
- Map an ingredient to a key only if it really is that food (fresh spinach = spinach;
  cream cheese is NOT heavy_cream). Otherwise canonical is null.
- For a mapped ingredient, give qty in the unit shown next to its key, or in
  g, kg, oz, lb, ml, l, tsp, tbsp or cup. Never give "count" for a g or ml key:
  estimate the weight instead (1 medium onion is about 150 g).
- Garlic is counted in cloves.

KEYS (unit): %s
"""


class NotARecipe(ValueError):
    """Gemini says the search isn't a dish (e.g. "my homework")."""


def normalize_name(name: str) -> str:
    return " ".join(name.lower().split())


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", normalize_name(name)).strip("-")


def to_recipe(data: Dict[str, Any], query: str) -> Recipe:
    """Turn Gemini's JSON into a Recipe. Raises ValueError if it isn't a usable recipe."""
    if not isinstance(data, dict) or not data.get("found"):
        raise NotARecipe(query)
    try:
        servings = int(data.get("servings") or 4)
    except (TypeError, ValueError):
        servings = 4
    servings = max(1, min(servings, MAX_SERVINGS))

    totals: Dict[str, float] = {}
    untracked: List[str] = []
    for ing in data.get("ingredients") or []:
        text = str(ing.get("text") or "").strip()
        canonical = ing.get("canonical")
        try:
            if not canonical or not catalog.is_known(canonical):
                raise ValueError("not in catalog")
            unit = normalize_unit(str(ing.get("unit") or ""))
            target = catalog.unit(canonical)
            if unit == "count" and target != "count":
                raise ValueError("a count of a weighed item is a guess")  # "1 onion" isn't a 450 g bag
            qty = to_base(float(ing.get("qty")), unit, target)
            if qty <= 0:
                raise ValueError("no amount")
            totals[canonical] = totals.get(canonical, 0.0) + qty
        except (ValueError, TypeError):
            if text:
                untracked.append(text)

    steps = [str(s).strip() for s in data.get("steps") or [] if str(s).strip()]
    if not totals and not untracked:
        raise ValueError("the recipe for %r came back without ingredients" % query)
    return Recipe(
        id="gen-" + slug(query),
        name=str(data.get("name") or query).strip()[:MAX_NAME_LEN],
        servings=servings,
        ingredients=[IngredientQty(canonical=c, qty_base=round(q, 1), unit_base=catalog.unit(c))
                     for c, q in totals.items()],
        steps=steps,
        untracked=untracked,
        generated=True,
    )


async def generate(query: str) -> Recipe:
    keys = ", ".join("%s (%s)" % (k, v["unit"]) for k, v in sorted(catalog.CANON.items()))
    data = await gemini.generate_json([{"text": PROMPT % (query.replace('"', "'"), keys)}], "recipe")
    return to_recipe(data, query)
