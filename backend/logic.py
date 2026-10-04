"""Deterministic food-waste math.

No LLM in this file: every quantity shown in the app is computed here, so a
number on screen is always right (or at least reproducible and testable).

Core ideas
- Inventory is a list of "lots" (one per purchase line), each with a purchase date and shelf life.
- Cooking takes from the lot that spoils soonest first.
- Anything we have to buy is bought in whole packages (catalog pack_size), and the
  unused part of a package becomes a virtual lot. That is what lets the planner see
  that two recipes sharing one tub of cream means less waste than two different tubs.
"""
import math
import random
import uuid
from datetime import date
from typing import Any, Dict, List, NamedTuple, Optional, Tuple

import catalog
from models import (
    InventoryItem, Leftover, PlannedMeal, PlanResult, Recipe, ShoppingItem, Suggestion,
)

EPS = 1e-6

# How much one ingredient line we must buy costs a recipe when ranking.
# Bigger number = the planner cares more about "no extra shopping" than "rescue more food".
# Tune this live if the suggestions look off during the demo.
MISSING_PENALTY = 10.0

# A "use it up" suggestion that needs more than this many extra ingredients isn't a rescue, it's a shopping trip.
MAX_MISSING_FOR_SUGGESTION = 2


# ---------------------------------------------------------------- basics

def clean_brand(brand: Any) -> Optional[str]:
    """A brand as Gemini wrote it, or None for blanks and non-answers ("unknown", "generic")."""
    text = " ".join(str(brand or "").split())[:40]
    if text.lower() in {"", "null", "none", "unknown", "generic", "n/a", "unbranded"}:
        return None
    return text


def make_lot(canonical: str, qty_base: float, today: date, brand: Optional[str] = None) -> InventoryItem:
    info = catalog.info(canonical)
    return InventoryItem(
        brand=clean_brand(brand),
        id=uuid.uuid4().hex[:8],
        canonical=canonical,
        display_name=info["display"],
        qty_base=round(qty_base, 2),
        unit_base=info["unit"],
        category=info["category"],
        purchased_on=today.isoformat(),
        shelf_life_days=info["shelf_life_days"],
    )


def days_left(item: InventoryItem, today: date) -> int:
    purchased = date.fromisoformat(item.purchased_on)
    return item.shelf_life_days - (today - purchased).days


def copy_lots(inventory: List[InventoryItem]) -> List[InventoryItem]:
    return [i.model_copy(deep=True) for i in inventory]


def _lots_for(lots: List[InventoryItem], canonical: str) -> List[InventoryItem]:
    return [l for l in lots if l.canonical == canonical and l.qty_base > EPS]


def required(recipe: Recipe, servings: int) -> Dict[str, float]:
    """Ingredient amounts (base units) needed to cook `servings` portions."""
    scale = servings / recipe.servings
    out: Dict[str, float] = {}
    for ing in recipe.ingredients:
        out[ing.canonical] = out.get(ing.canonical, 0.0) + ing.qty_base * scale
    return out


def describe(canonical: str, qty: float) -> str:
    n = int(round(qty))
    name = catalog.display(canonical).lower()
    if catalog.unit(canonical) == "count":
        return "%d %s" % (n, name)
    return "%d %s %s" % (n, catalog.unit(canonical), name)


def consume(lots: List[InventoryItem], canonical: str, need: float, today: date) -> float:
    """Take `need` from lots (soonest-to-spoil first). Mutates lots.
    Returns the amount that could NOT be covered (0 if we had enough)."""
    for lot in sorted(_lots_for(lots, canonical), key=lambda l: days_left(l, today)):
        take = min(lot.qty_base, need)
        lot.qty_base -= take
        need -= take
        if need <= EPS:
            return 0.0
    return need


def set_total(lots: List[InventoryItem], canonical: str, qty: float, today: date,
              brand: Optional[str] = None) -> None:
    """Make the pantry hold exactly `qty` of `canonical` (mutates lots), e.g. after a fridge photo.
    Less than we thought: take the difference from the soonest-to-spoil lots, the ones most
    likely already used. More: the extra becomes a new lot bought today.
    A brand seen on the package is newer than what we knew, so it's set on every lot."""
    have = sum(l.qty_base for l in _lots_for(lots, canonical))
    if qty < have - EPS:
        consume(lots, canonical, have - qty, today)
    elif qty > have + EPS:
        lots.append(make_lot(canonical, qty - have, today, brand))
    if clean_brand(brand):
        for lot in _lots_for(lots, canonical):
            lot.brand = clean_brand(brand)


def apply_meal(
    lots: List[InventoryItem],
    recipe: Recipe,
    servings: int,
    today: date,
    short: Optional[Dict[str, float]] = None,
    bought: Optional[Dict[str, float]] = None,
) -> None:
    """Cook one meal against `lots` (mutates them).

    short  - if given, shortfalls are recorded here (what we did not have).
    bought - if given, shortfalls are "bought" in whole packages: the bought amount is
             recorded here and the unused remainder is added to `lots` as a fresh lot.
    """
    for canonical, need in required(recipe, servings).items():
        gap = consume(lots, canonical, need, today)
        if gap <= EPS:
            continue
        if short is not None:
            short[canonical] = short.get(canonical, 0.0) + gap
        if bought is not None:
            pack = catalog.pack_size(canonical)
            qty = math.ceil(gap / pack - EPS) * pack
            bought[canonical] = bought.get(canonical, 0.0) + qty
            if qty - gap > EPS:
                lots.append(make_lot(canonical, qty - gap, today))


def to_shopping(qtys: Dict[str, float], round_to_packs: bool = True) -> List[ShoppingItem]:
    items = []
    for canonical, q in qtys.items():
        if q <= EPS:
            continue
        if round_to_packs:
            pack = catalog.pack_size(canonical)
            q = math.ceil(q / pack - EPS) * pack
        items.append(ShoppingItem(
            canonical=canonical,
            display_name=catalog.display(canonical),
            qty_base=round(q, 1),
            unit_base=catalog.unit(canonical),
        ))
    return sorted(items, key=lambda s: s.display_name)


def leftovers_for(lots: List[InventoryItem], canonicals: List[str], today: date) -> List[Leftover]:
    out = []
    for c in canonicals:
        ls = _lots_for(lots, c)
        if not ls:
            continue
        out.append(Leftover(
            canonical=c,
            display_name=catalog.display(c),
            qty_base=round(sum(l.qty_base for l in ls), 1),
            unit_base=catalog.unit(c),
            days_until_spoil=min(days_left(l, today) for l in ls),
        ))
    return sorted(out, key=lambda l: l.days_until_spoil)


def waste_grams(lots: List[InventoryItem]) -> float:
    """Grams of perishable food sitting unused in `lots`."""
    return sum(
        catalog.grams_equiv(l.canonical, l.qty_base)
        for l in lots if l.qty_base > EPS and catalog.is_perishable(l.canonical)
    )


# ---------------------------------------------------------------- preview / cook

def preview(inventory: List[InventoryItem], meals: List[Tuple[Recipe, int]], today: date) -> PlanResult:
    """What is left (and what is missing) if we cook these meals? Nothing is saved."""
    lots = copy_lots(inventory)
    short: Dict[str, float] = {}
    touched: List[str] = []
    for recipe, servings in meals:
        for c in required(recipe, servings):
            if c not in touched:
                touched.append(c)
        apply_meal(lots, recipe, servings, today, short=short)
    return PlanResult(leftovers=leftovers_for(lots, touched, today), missing=to_shopping(short))


class CookOutcome(NamedTuple):
    lots: List[InventoryItem]
    touched: List[str]
    saved_g: float
    saved_usd: float
    saved_co2e: float


def cook(inventory: List[InventoryItem], recipe: Recipe, servings: int,
         from_suggestion: bool, today: date) -> CookOutcome:
    """Actually cook: returns the new inventory plus how much food we 'rescued'.
    Rescued = perishable food already in the pantry that a suggested recipe used up."""
    need = required(recipe, servings)
    saved_g = saved_usd = saved_co2e = 0.0
    if from_suggestion:
        for c, q in need.items():
            if not catalog.is_perishable(c):
                continue
            have = sum(l.qty_base for l in _lots_for(inventory, c))
            used = min(have, q)
            if used > EPS:
                saved_g += catalog.grams_equiv(c, used)
                saved_usd += catalog.price(c, used)
                saved_co2e += catalog.co2e(c, used)
    lots = copy_lots(inventory)
    apply_meal(lots, recipe, servings, today)
    lots = [l for l in lots if l.qty_base > EPS]
    return CookOutcome(lots, list(need.keys()), saved_g, saved_usd, saved_co2e)


# ---------------------------------------------------------------- ranking

def score_recipe(lots: List[InventoryItem], recipe: Recipe, servings: int, today: date):
    """Higher = better. Rewards using up perishables that are about to spoil,
    penalises every ingredient we would have to go buy.
    Returns (score, rescued_labels, shortfalls, soonest_days)."""
    rescued_score = 0.0
    rescued: List[str] = []
    short: Dict[str, float] = {}
    soonest: Optional[int] = None
    for canonical, need in required(recipe, servings).items():
        ls = _lots_for(lots, canonical)
        have = sum(l.qty_base for l in ls)
        used = min(have, need)
        if need - have > EPS:
            short[canonical] = need - have
        if used > EPS and catalog.is_perishable(canonical):
            d = min(days_left(l, today) for l in ls)
            urgency = 1.0 / max(d, 1)
            rescued_score += catalog.grams_equiv(canonical, used) * urgency
            rescued.append(describe(canonical, used))
            soonest = d if soonest is None else min(soonest, d)
    score = rescued_score - MISSING_PENALTY * len(short)
    return score, rescued, short, soonest


def _reason(rescued: List[str], short: Dict[str, float], soonest: Optional[int]) -> str:
    parts = []
    if rescued:
        text = "Uses up " + ", ".join(rescued)
        if soonest is not None:
            if soonest <= 0:
                text += " (expiring today)"
            else:
                text += " (soonest spoils in %d day%s)" % (soonest, "" if soonest == 1 else "s")
        parts.append(text + ".")
    if short:
        parts.append("Still need: " + ", ".join(catalog.display(c).lower() for c in short) + ".")
    else:
        parts.append("Nothing extra to buy.")
    return " ".join(parts)


def suggest(inventory: List[InventoryItem], recipes: List[Recipe], today: date,
            limit: int = 5) -> List[Suggestion]:
    """Recipes that rescue perishables we already own, best first."""
    ranked = []
    for r in recipes:
        score, rescued, short, soonest = score_recipe(inventory, r, r.servings, today)
        if not rescued or len(short) > MAX_MISSING_FOR_SUGGESTION:
            continue
        ranked.append((score, r, rescued, short, soonest))
    ranked.sort(key=lambda t: -t[0])
    return [
        Suggestion(recipe=r, reason=_reason(rescued, short, soonest), rescued=rescued,
                   missing=to_shopping(short), score=round(score, 1))
        for score, r, rescued, short, soonest in ranked[:limit]
    ]


def describe_recipe(inventory: List[InventoryItem], recipe: Recipe, today: date) -> Suggestion:
    """Any recipe (e.g. one found by search), described against the pantry like a suggestion."""
    score, rescued, short, soonest = score_recipe(inventory, recipe, recipe.servings, today)
    return Suggestion(recipe=recipe, reason=_reason(rescued, short, soonest), rescued=rescued,
                      missing=to_shopping(short), score=round(score, 1))


def plan_week(inventory: List[InventoryItem], recipes: List[Recipe], n: int, today: date):
    """Greedy planner: repeatedly pick the recipe with the best score, cook it virtually,
    buy missing food in whole packages, and let later recipes reuse the package leftovers.
    Returns (meals, shopping_list, projected_waste_g, baseline_waste_g)."""
    n = max(1, min(n, len(recipes)))
    lots = copy_lots(inventory)
    available = list(recipes)
    bought: Dict[str, float] = {}
    meals: List[PlannedMeal] = []
    for _ in range(n):
        best = max(available, key=lambda r: score_recipe(lots, r, r.servings, today)[0])
        _, rescued, short, soonest = score_recipe(lots, best, best.servings, today)
        apply_meal(lots, best, best.servings, today, bought=bought)
        meals.append(PlannedMeal(recipe=best, servings=best.servings,
                                 reason=_reason(rescued, short, soonest)))
        available.remove(best)
    return (
        meals,
        to_shopping(bought, round_to_packs=False),
        round(waste_grams(lots), 1),
        round(baseline_waste(inventory, recipes, n, today), 1),
    )


def baseline_waste(inventory: List[InventoryItem], recipes: List[Recipe], n: int,
                   today: date, samples: int = 200, seed: int = 7) -> float:
    """Average perishable waste if you picked n random recipes from the same book
    and bought whatever was missing in whole packages. This is the 'before' number."""
    rng = random.Random(seed)
    n = max(1, min(n, len(recipes)))
    total = 0.0
    for _ in range(samples):
        lots = copy_lots(inventory)
        bought: Dict[str, float] = {}
        for r in rng.sample(recipes, n):
            apply_meal(lots, r, r.servings, today, bought=bought)
        total += waste_grams(lots)
    return total / samples
