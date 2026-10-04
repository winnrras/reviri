from datetime import date, timedelta

import pytest

import catalog
import logic
import receipt
from models import ShoppingItem
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


def test_rows_to_items_garlic_bulb_is_a_pack_of_cloves():
    rows = [{"raw": "GARLIC BULB", "canonical": "garlic", "qty": 2, "unit": "count"},
            {"raw": "LEMONS 3 @ 0.69", "canonical": "lemon", "qty": 3, "unit": "count"}]
    got = {i.canonical: i.qty_base for i in receipt.rows_to_items(rows, TODAY)}
    assert got["garlic"] == 2 * catalog.pack_size("garlic")
    assert got["lemon"] == 3              # ordinary count items are unchanged


def test_half_gallon_of_milk():
    rows = [{"raw": "2% MILK 1/2 GAL", "canonical": "milk", "qty": 0.5, "unit": "gal"}]
    assert receipt.rows_to_items(rows, TODAY)[0].qty_base == pytest.approx(1892.7, abs=0.1)


# ---- streak

def test_streak_counts_consecutive_days_and_resets_after_gap(store):
    store.check_in(TODAY)
    store.check_in(TODAY)                          # same day: no double count
    assert store.streak_days == 1
    store.check_in(TODAY + timedelta(days=1))
    assert store.streak_days == 2
    store.check_in(TODAY + timedelta(days=4))      # missed days
    assert store.streak_days == 1


# ---- fridge photos (no network)

import fridge


def test_fridge_estimate_fill_size_and_pieces():
    half_gallon = {"canonical": "milk", "how": "container", "containers": 1, "fill": "half",
                   "size_qty": 1, "size_unit": "gal", "size_printed": True}
    assert fridge.estimate(half_gallon)[0] == pytest.approx(1892.7, abs=0.1)
    cup = {"canonical": "yogurt", "how": "container", "fill": "full",
           "size_qty": 150, "size_unit": "g", "size_printed": False}
    qty, note = fridge.estimate(cup)
    assert qty == 150 and note.startswith("about")
    no_size = {"canonical": "butter", "how": "container", "fill": "most"}
    assert fridge.estimate(no_size)[0] == pytest.approx(0.75 * catalog.pack_size("butter"))
    assert fridge.estimate({"canonical": "eggs", "how": "pieces", "pieces": 5})[0] == 5
    assert fridge.estimate({"canonical": "onion", "how": "weight", "grams": 300})[0] == 300


def test_fridge_proposals_update_add_untracked_and_merge():
    inventory = [logic.make_lot("soy_sauce", 296, TODAY)]
    rows = [
        {"label": "Kikkoman", "canonical": "soy_sauce", "how": "container", "fill": "half"},
        {"label": "Skim milk", "canonical": "milk", "how": "container", "fill": "full"},
        {"label": "Milk", "canonical": "milk", "how": "container", "fill": "half"},
        {"label": "Canola oil", "canonical": None, "how": "container"},
        {"label": "Mystery", "canonical": "dragonfruit", "how": "container"},
    ]
    got = {p.label: p for p in fridge.to_proposals(rows, inventory)}
    soy = got["Kikkoman"]
    assert soy.action == "update" and soy.pantry_qty == 296 and soy.qty_base == 148
    milk = got["Skim milk + Milk"]
    assert milk.action == "add" and milk.qty_base == pytest.approx(1.5 * 946)
    assert got["Canola oil"].action == "untracked" and got["Mystery"].action == "untracked"


def test_set_total_takes_from_soonest_spoiling_or_adds_a_lot():
    old = logic.make_lot("milk", 500, TODAY - timedelta(days=5))
    new = logic.make_lot("milk", 946, TODAY)
    lots = [old, new]
    logic.set_total(lots, "milk", 700, TODAY)
    assert old.qty_base == 0 and new.qty_base == 700        # the older carton went first
    logic.set_total(lots, "milk", 1000, TODAY)
    assert sum(l.qty_base for l in lots if l.canonical == "milk") == pytest.approx(1000)
    assert lots[-1].qty_base == pytest.approx(300)           # the extra is a new lot


def test_brands_from_receipts_fridge_and_cleanup():
    assert logic.clean_brand("  Kikkoman ") == "Kikkoman"
    assert logic.clean_brand("unknown") is None and logic.clean_brand(None) is None
    items = receipt.rows_to_items([{"raw": "KRO SHRP CHED", "canonical": "cheddar", "qty": 8, "unit": "oz",
                                    "brand": "Kroger"}], TODAY)
    assert items[0].brand == "Kroger"
    rows = [{"label": "Kikkoman Soy Sauce", "brand": "Kikkoman", "canonical": "soy_sauce", "how": "container"},
            {"label": "Milk", "brand": "null", "canonical": "milk", "how": "container"}]
    got = {p.canonical: p for p in fridge.to_proposals(rows, [])}
    assert got["soy_sauce"].brand == "Kikkoman" and got["milk"].brand is None


def test_set_total_records_the_brand_seen():
    lots = [logic.make_lot("soy_sauce", 296, TODAY)]
    logic.set_total(lots, "soy_sauce", 150, TODAY, "Kikkoman")
    assert [l.brand for l in lots if l.qty_base > 0] == ["Kikkoman"]
    logic.set_total(lots, "milk", 946, TODAY, "Horizon")
    assert lots[-1].canonical == "milk" and lots[-1].brand == "Horizon"


def test_tossing_counts_as_waste_but_never_touches_the_streak(store):
    store.inventory = demo_pantry()
    store.check_in(TODAY)
    spinach = next(l for l in store.inventory if l.canonical == "spinach")
    assert store.remove(spinach.id, tossed=True)
    assert store.stats(TODAY).wasted_g == pytest.approx(283)
    assert store.streak_days == 1
    eggs = next(l for l in store.inventory if l.canonical == "eggs")
    assert store.remove(eggs.id, tossed=False)            # used: no waste recorded
    assert store.stats(TODAY).wasted_g == pytest.approx(283)
    assert not store.remove("nope", tossed=True)


def test_expired_items_are_listed_until_dealt_with(store):
    store.inventory = demo_pantry()
    later = TODAY + timedelta(days=3)                     # chicken (2-day shelf life) is now past its date
    assert [l.canonical for l in store.expired(later)] == ["chicken_breast"]
    assert store.stats(later).expired == ["Chicken breast"]
    chicken = store.expired(later)[0]
    store.remove(chicken.id, tossed=True)
    assert store.expired(later) == []


# ---- text alerts (no sending)

import notify


def test_normalize_phone():
    assert notify.normalize_phone("(555) 123-4567") == "+15551234567"
    assert notify.normalize_phone("1-555-123-4567") == "+15551234567"
    assert notify.normalize_phone("+62 812 3456 7890") == "+6281234567890"
    assert notify.normalize_phone("12345") is None and notify.normalize_phone("") is None


def test_spoil_alert_lists_today_and_tomorrow_only():
    shelf = lambda c: catalog.info(c)["shelf_life_days"]
    inv = [logic.make_lot("chicken_breast", 680, TODAY - timedelta(days=shelf("chicken_breast") - 1)),  # 1 day left
           logic.make_lot("spinach", 283, TODAY - timedelta(days=shelf("spinach"))),                     # 0 days left
           logic.make_lot("rice", 907, TODAY),                                                           # stable
           logic.make_lot("milk", 946, TODAY - timedelta(days=shelf("milk") + 2))]                       # expired: not "by tomorrow"
    text = notify.spoil_alert_text(inv, [], TODAY)
    assert text.splitlines() == ["Reviri: use these by tomorrow",
                                 "- Spinach, 283 g (spoils today)",
                                 "- Chicken breast, 680 g (spoils tomorrow)"]
    assert notify.spoil_alert_text([logic.make_lot("rice", 907, TODAY)], [], TODAY) is None


def test_shopping_list_text():
    items = [ShoppingItem(canonical="pasta", display_name="Pasta", qty_base=454, unit_base="g"),
             ShoppingItem(canonical="eggs", display_name="Eggs", qty_base=12, unit_base="count")]
    assert notify.shopping_list_text("Chicken Alfredo", items) == \
        "Reviri shopping list: Chicken Alfredo\n- Pasta, 454 g\n- Eggs, 12 pcs"


def test_rows_to_items_reports_untracked_food_lines():
    skipped = []
    rows = [{"raw": "BANANAS 2.4 LB", "canonical": None, "qty": 2.4, "unit": "lb"},
            {"raw": "BROCCOLI CROWNS", "canonical": "broccoli", "qty": 0.85, "unit": "lb"}]
    items = receipt.rows_to_items(rows, TODAY, skipped)
    assert [i.canonical for i in items] == ["broccoli"] and skipped == ["BANANAS 2.4 LB"]
