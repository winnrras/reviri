from datetime import date, timedelta

import pytest

import catalog
import logic
import receipt
from store import STAPLES, Store
from units import to_base

TODAY = date(2026, 10, 3)


@pytest.fixture
def store():
    return Store()


def demo_pantry():
    """Starting staples (same as a freshly reset app) plus the demo receipt."""
    staples = [logic.make_lot(c, q, TODAY) for c, q in STAPLES]
    return staples + receipt.demo_items(TODAY)


def recipe(store, rid):
    return store.recipe(rid)


# ---- data consistency

def test_every_recipe_ingredient_is_in_catalog_with_matching_unit(store):
    for r in store.recipes:
        for ing in r.ingredients:
            assert catalog.is_known(ing.canonical), (r.id, ing.canonical)
            assert ing.unit_base == catalog.unit(ing.canonical), (r.id, ing.canonical)


# ---- units

def test_unit_conversions():
    assert to_base(16, "oz", "g") == pytest.approx(453.592, rel=1e-3)
    assert to_base(1, "lb", "g") == pytest.approx(453.592, rel=1e-3)
    assert to_base(2, "tbsp", "ml") == pytest.approx(29.57, rel=1e-3)
    assert to_base(1.5, "kg", "g") == 1500


def test_oz_means_fluid_ounces_for_liquids():
    assert to_base(16, "oz", "ml") == pytest.approx(473.2, rel=1e-3)


def test_count_of_gram_item_means_whole_packs():
    assert to_base(2, "count", "g", pack_size=283) == 566


def test_unknown_unit_raises():
    with pytest.raises(ValueError):
        to_base(1, "bushel", "g")


# ---- leftover math

def test_demo_leftovers_after_creamy_spinach_chicken(store):
    res = logic.preview(demo_pantry(), [(recipe(store, "creamy-spinach-chicken"), 4)], TODAY)
    left = {l.canonical: l.qty_base for l in res.leftovers}
    assert left["heavy_cream"] == pytest.approx(473 - 240)
    assert left["spinach"] == pytest.approx(283 - 150)
    assert "chicken_breast" not in left          # used up completely
    assert res.missing == []


def test_servings_scale_ingredients(store):
    half = logic.required(recipe(store, "creamy-spinach-chicken"), 2)
    assert half["heavy_cream"] == pytest.approx(120)


def test_missing_items_are_reported_in_whole_packs(store):
    res = logic.preview([], [(recipe(store, "mushroom-cream-pasta"), 4)], TODAY)
    missing = {m.canonical: m.qty_base for m in res.missing}
    assert missing["pasta"] == 454            # need 400, sold in 454 g packs
    assert missing["heavy_cream"] == 473


def test_consumes_soonest_to_spoil_first():
    old = logic.make_lot("spinach", 100, TODAY - timedelta(days=3))
    new = logic.make_lot("spinach", 100, TODAY)
    lots = [new, old]
    assert logic.consume(lots, "spinach", 120, TODAY) == 0
    assert old.qty_base == pytest.approx(0)
    assert new.qty_base == pytest.approx(80)


def test_cook_does_not_mutate_input(store):
    pantry = demo_pantry()
    logic.cook(pantry, recipe(store, "creamy-spinach-chicken"), 4, False, TODAY)
    assert next(l for l in pantry if l.canonical == "spinach").qty_base == 283


# ---- suggestions

def test_quiche_is_top_suggestion_after_creamy_spinach_chicken(store):
    after = logic.cook(demo_pantry(), recipe(store, "creamy-spinach-chicken"), 4, False, TODAY).lots
    sugg = logic.suggest(after, store.recipes, TODAY)
    assert sugg[0].recipe.id == "spinach-mushroom-quiche"
    assert sugg[0].missing == []
    assert "spinach" in sugg[0].reason.lower()


def test_just_cooked_meal_is_not_suggested_again(store):
    after = logic.cook(demo_pantry(), recipe(store, "creamy-spinach-chicken"), 4, False, TODAY).lots
    ids = [s.recipe.id for s in logic.suggest(after, store.recipes, TODAY)]
    assert "creamy-spinach-chicken" not in ids


def test_cooking_a_suggestion_counts_rescued_food(store):
    after = logic.cook(demo_pantry(), recipe(store, "creamy-spinach-chicken"), 4, False, TODAY).lots
    out = logic.cook(after, recipe(store, "spinach-mushroom-quiche"), 6, True, TODAY)
    assert out.saved_g == pytest.approx(100 + 120 + 150)   # spinach + cream + mushrooms
    plain = logic.cook(after, recipe(store, "spinach-mushroom-quiche"), 6, False, TODAY)
    assert plain.saved_g == 0


def test_no_suggestions_for_empty_pantry(store):
    assert logic.suggest([], store.recipes, TODAY) == []


# ---- planner

def test_plan_week_returns_n_distinct_meals_and_nonnegative_list(store):
    meals, shopping, projected, baseline = logic.plan_week(demo_pantry(), store.recipes, 4, TODAY)
    assert len(meals) == 4
    assert len({m.recipe.id for m in meals}) == 4
    assert all(s.qty_base > 0 for s in shopping)


def test_plan_beats_random_baseline(store):
    meals, shopping, projected, baseline = logic.plan_week(demo_pantry(), store.recipes, 4, TODAY)
    assert projected <= baseline


def test_plan_uses_pantry_perishables_first(store):
    meals, *_ = logic.plan_week(demo_pantry(), store.recipes, 3, TODAY)
    assert meals[0].recipe.id in {"creamy-spinach-chicken", "spinach-mushroom-quiche"}


def test_plan_week_on_empty_pantry_still_works(store):
    meals, shopping, projected, baseline = logic.plan_week([], store.recipes, 3, TODAY)
    assert len(meals) == 3 and shopping


# ---- receipt parsing (no network)

def test_rows_to_items_maps_and_skips_unknown():
    rows = [
        {"raw": "ORG BNLS CHKN BRST 1.5LB", "canonical": "chicken_breast", "qty": 1.5, "unit": "lb"},
        {"raw": "HVY CRM 16OZ", "canonical": "heavy_cream", "qty": 16, "unit": "oz"},
        {"raw": "SPINACH", "canonical": "spinach", "qty": 1, "unit": "count"},
        {"raw": "GLITTER", "canonical": None, "qty": 1, "unit": "count"},
        {"raw": "WEIRD", "canonical": "mushrooms", "qty": 3, "unit": "bushel"},
    ]
    items = receipt.rows_to_items(rows, TODAY)
    got = {i.canonical: i.qty_base for i in items}
    assert got["chicken_breast"] == pytest.approx(680.4, abs=0.1)
    assert got["heavy_cream"] == pytest.approx(473.2, abs=0.1)
    assert got["spinach"] == 283          # one pack
    assert got["mushrooms"] == 227        # unreadable unit -> one pack
    assert len(items) == 4


# ---- streak

def test_streak_counts_consecutive_days_and_resets_after_gap(store):
    store.check_in(TODAY)
    store.check_in(TODAY)                          # same day: no double count
    assert store.streak_days == 1
    store.check_in(TODAY + timedelta(days=1))
    assert store.streak_days == 2
    store.check_in(TODAY + timedelta(days=4))      # missed days
    assert store.streak_days == 1
