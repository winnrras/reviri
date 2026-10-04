"""End-to-end test of the demo script, through the real HTTP API."""
import pytest
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def fresh():
    client.post("/reset")
    yield


def test_health():
    assert client.get("/health").json()["ok"] is True


def test_recipes_listed():
    r = client.get("/recipes").json()
    assert len(r) >= 8 and {"id", "name", "servings", "ingredients"} <= set(r[0])


def test_full_demo_flow():
    # 1. scan the demo receipt
    items = client.post("/demo-receipt").json()
    assert {i["canonical"] for i in items} >= {"chicken_breast", "heavy_cream", "spinach"}
    assert all(i["days_left"] is not None for i in items)

    # 2. preview Creamy Spinach Chicken for 4
    plan = client.post("/plan", json={"picks": [{"recipe_id": "creamy-spinach-chicken", "servings": 4}]}).json()
    left = {l["canonical"]: l["qty_base"] for l in plan["leftovers"]}
    assert left["heavy_cream"] == pytest.approx(233)
    assert left["spinach"] == pytest.approx(133)
    assert plan["missing"] == []

    # preview must not change the pantry
    inv = {i["canonical"]: i["qty_base"] for i in client.get("/inventory").json()}
    assert inv["spinach"] == pytest.approx(283)

    # 3. cook it
    cooked = client.post("/cook", json={"recipe_id": "creamy-spinach-chicken", "servings": 4}).json()
    assert cooked["stats"]["grams_saved"] == 0

    # 4. suggestion = quiche
    sugg = client.get("/suggestions").json()["suggestions"]
    assert sugg[0]["recipe"]["id"] == "spinach-mushroom-quiche"

    # 5. cook the suggestion, stats go up
    after = client.post("/cook", json={"recipe_id": "spinach-mushroom-quiche", "servings": 6,
                                       "from_suggestion": True}).json()
    assert after["stats"]["grams_saved"] == pytest.approx(370)
    assert after["stats"]["dollars_saved"] > 0 and after["stats"]["co2e_saved"] > 0

    # 6. plan ahead
    nw = client.post("/next-week", json={"meals": 3}).json()
    assert len(nw["meals"]) == 3
    assert nw["projected_waste_g"] <= nw["baseline_waste_g"]

    # 7. streak
    assert client.post("/checkin").json()["streak_days"] == 1
    assert client.post("/checkin").json()["streak_days"] == 1
    assert client.get("/stats").json()["checked_in_today"] is True


def test_edit_and_delete_item():
    items = client.post("/demo-receipt").json()
    spinach = next(i for i in items if i["canonical"] == "spinach")
    spinach["qty_base"] = 100
    assert client.put("/inventory/" + spinach["id"], json=spinach).json()["qty_base"] == 100
    assert client.delete("/inventory/" + spinach["id"]).json() == {"ok": True}
    assert client.delete("/inventory/" + spinach["id"]).status_code == 404


def test_parse_receipt_without_key_falls_back_to_demo(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    r = client.post("/parse-receipt", files={"file": ("r.jpg", b"fake-bytes", "image/jpeg")})
    assert r.status_code == 200 and len(r.json()) == 10


def test_unknown_recipe_is_404():
    r = client.post("/plan", json={"picks": [{"recipe_id": "nope", "servings": 2}]})
    assert r.status_code == 404


# ---- recipe search (Gemini replaced by a fixed answer)

ALFREDO = {
    "found": True, "name": "Chicken Alfredo", "servings": 4,
    "ingredients": [
        {"text": "1 lb chicken breast", "canonical": "chicken_breast", "qty": 1, "unit": "lb"},
        {"text": "1 cup heavy cream", "canonical": "heavy_cream", "qty": 1, "unit": "cup"},
        {"text": "2 tbsp butter", "canonical": "butter", "qty": 2, "unit": "tbsp"},
        {"text": "3 cloves garlic", "canonical": "garlic", "qty": 3, "unit": "cloves"},
        {"text": "1 onion", "canonical": "onion", "qty": 1, "unit": "count"},
        {"text": "12 oz fettuccine", "canonical": "pasta", "qty": 12, "unit": "oz"},
        {"text": "1 tsp paprika", "canonical": None, "qty": 1, "unit": "tsp"},
    ],
    "steps": ["Cook the pasta.", "Sear the chicken.", "Simmer cream and butter, toss together."],
}


@pytest.fixture
def fake_gemini(monkeypatch):
    calls = []

    async def fake(parts, label):
        calls.append(parts[0]["text"])
        return ALFREDO

    import gemini
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setattr(gemini, "generate_json", fake)
    import main
    main.store.generated.clear()
    return calls


def test_generate_recipe_maps_ingredients_and_plugs_into_pantry(fake_gemini):
    client.post("/demo-receipt")
    s = client.post("/recipes/generate", json={"name": "  Chicken  ALFREDO "}).json()
    r = s["recipe"]
    assert r["id"] == "gen-chicken-alfredo" and r["generated"] is True and len(r["steps"]) == 3
    got = {i["canonical"]: i["qty_base"] for i in r["ingredients"]}
    assert got["chicken_breast"] == pytest.approx(453.6, abs=0.1)
    assert got["heavy_cream"] == pytest.approx(236.6, abs=0.1)
    assert got["garlic"] == 3                          # cloves, not bulbs
    assert "onion" not in got                          # "1 onion" as a count is a guess: not tracked
    assert r["untracked"] == ["1 onion", "1 tsp paprika"]
    assert "chicken breast" in s["reason"]             # uses up the scanned chicken
    assert [m["canonical"] for m in s["missing"]] == ["pasta"]

    # Cookable and plannable like any recipe, and listed for the Plan tab.
    assert client.post("/plan", json={"picks": [{"recipe_id": r["id"], "servings": 4}]}).status_code == 200
    assert client.post("/cook", json={"recipe_id": r["id"], "servings": 4}).status_code == 200
    assert r["id"] in [x["id"] for x in client.get("/recipes").json()]
    # ...but never mixed into the suggestions or the waste-forecast book.
    assert r["id"] not in [x["recipe"]["id"] for x in client.get("/suggestions").json()["suggestions"]]


def test_generate_recipe_is_cached(fake_gemini):
    client.post("/recipes/generate", json={"name": "chicken alfredo"})
    client.post("/recipes/generate", json={"name": "Chicken Alfredo"})
    assert len(fake_gemini) == 1


def test_generate_recipe_not_a_dish(monkeypatch, fake_gemini):
    import gemini

    async def nope(parts, label):
        return {"found": False}

    monkeypatch.setattr(gemini, "generate_json", nope)
    assert client.post("/recipes/generate", json={"name": "my homework"}).status_code == 422


def test_generate_recipe_needs_key_and_a_name(monkeypatch):
    import main
    main.store.generated.clear()
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    assert client.post("/recipes/generate", json={"name": "pad thai"}).status_code == 503
    assert client.post("/recipes/generate", json={"name": "   "}).status_code == 400


# ---- fridge photos (Gemini replaced by a fixed answer)

def test_scan_fridge_proposes_then_apply_updates_without_doubling(monkeypatch):
    async def fake(parts, label, model=None):
        return [{"label": "Mainland Butter", "brand": "Mainland", "canonical": "butter", "how": "container",
                 "fill": "half"},
                {"label": "Skim milk 1 gal", "canonical": "milk", "how": "container", "fill": "half",
                 "size_qty": 1, "size_unit": "gal", "size_printed": True},
                {"label": "Ketchup", "canonical": None, "how": "container"}]

    import gemini
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setattr(gemini, "generate_json", fake)
    client.post("/demo-receipt")                                   # 227 g butter in the pantry
    before = client.get("/inventory").json()

    items = client.post("/scan-fridge", files={"file": ("f.jpg", b"img", "image/jpeg")}).json()["items"]
    by = {i["label"]: i for i in items}
    assert by["Mainland Butter"]["action"] == "update" and by["Mainland Butter"]["pantry_qty"] == 227
    assert by["Skim milk 1 gal"]["action"] == "add"
    assert by["Ketchup"]["action"] == "untracked"
    assert client.get("/inventory").json() == before               # scanning saves nothing

    inv = client.post("/fridge/apply", json={"items": [
        {"canonical": "butter", "qty_base": 113.5}, {"canonical": "milk", "qty_base": 1892.7}]}).json()
    totals = {}
    for i in inv:
        totals[i["canonical"]] = totals.get(i["canonical"], 0) + i["qty_base"]
    assert totals["butter"] == pytest.approx(113.5)                 # updated, not a second pack
    assert totals["milk"] == pytest.approx(1892.7)

    # The brand read on the package is kept and shown in the pantry.
    assert by["Mainland Butter"]["brand"] == "Mainland"
    inv = client.post("/fridge/apply", json={"items": [
        {"canonical": "butter", "qty_base": 113.5, "brand": "Mainland"}]}).json()
    assert {i["brand"] for i in inv if i["canonical"] == "butter"} == {"Mainland"}


def test_fridge_apply_rejects_bad_input():
    assert client.post("/fridge/apply", json={"items": [{"canonical": "unicorn", "qty_base": 1}]}).status_code == 400
    assert client.post("/fridge/apply", json={"items": [{"canonical": "milk", "qty_base": -1}]}).status_code == 400


def test_scan_fridge_needs_key(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    r = client.post("/scan-fridge", files={"file": ("f.jpg", b"img", "image/jpeg")})
    assert r.status_code == 503


def test_checkin_blocked_by_expired_food_until_tossed():
    import main
    from datetime import date, timedelta
    client.post("/demo-receipt")
    chicken = next(l for l in main.store.inventory if l.canonical == "chicken_breast")
    chicken.purchased_on = (date.today() - timedelta(days=5)).isoformat()   # now past its date

    r = client.post("/checkin")
    assert r.status_code == 409 and "chicken breast expired" in r.json()["detail"]
    assert client.get("/stats").json()["expired"] == ["Chicken breast"]

    assert client.delete("/inventory/%s?reason=tossed" % chicken.id).status_code == 200
    stats = client.post("/checkin").json()
    assert stats["streak_days"] == 1 and stats["wasted_g"] == 680 and stats["expired"] == []
    assert client.delete("/inventory/x?reason=lost").status_code == 400


def test_demo_skip_days_ages_the_pantry_not_the_streak():
    client.post("/demo-receipt")
    assert client.post("/checkin").json()["streak_days"] == 1
    inv = client.post("/demo/skip-days?days=3").json()
    chicken = next(i for i in inv if i["canonical"] == "chicken_breast")
    assert chicken["days_left"] == -1                              # 2-day shelf life, 3 days later
    stats = client.get("/stats").json()
    assert "Chicken breast" in stats["expired"] and stats["streak_days"] == 1
    assert client.post("/demo/skip-days?days=0").status_code == 400


def test_demo_undo_skip_restores_dates_but_not_further():
    client.post("/demo-receipt")
    fresh = {i["id"]: i["days_left"] for i in client.get("/inventory").json()}
    client.post("/demo/skip-days?days=3")
    back = {i["id"]: i["days_left"] for i in client.post("/demo/skip-days?days=-3").json()}
    assert back == fresh
    again = {i["id"]: i["days_left"] for i in client.post("/demo/skip-days?days=-3").json()}
    assert again == fresh                                          # nothing to undo: no change


# ---- text alerts (Photon replaced by a fake sender)

@pytest.fixture
def sent(monkeypatch):
    import main
    import notify
    box = []

    async def fake_send(to, text):
        box.append((to, text))
        return "local"

    monkeypatch.setattr(notify, "send_text", fake_send)
    main.store.alert_phone, main.store.alerts_enabled = None, False
    return box


def test_alert_settings_validate_and_survive_reset(sent):
    assert client.put("/alerts", json={"phone": "12", "enabled": True}).status_code == 400
    s = client.put("/alerts", json={"phone": "(555) 123-4567", "enabled": True}).json()
    assert s["phone"] == "+15551234567" and s["enabled"] is True and s["mode"] in ("local", "cloud")
    client.post("/reset")
    assert client.get("/alerts").json()["phone"] == "+15551234567"
    assert client.put("/alerts", json={"phone": "", "enabled": True}).json()["enabled"] is False


def test_test_alert_and_shopping_list_are_sent(sent):
    assert client.post("/alerts/test").status_code == 400            # no phone yet
    client.put("/alerts", json={"phone": "5551234567", "enabled": False})
    client.post("/demo-receipt")
    client.post("/demo/skip-days?days=1")                             # chicken: 1 day left
    r = client.post("/alerts/test").json()
    assert sent[-1] == ("+15551234567", r["text"]) and "Chicken breast" in r["text"]

    body = {"title": "Chicken Alfredo",
            "items": [{"canonical": "pasta", "display_name": "Pasta", "qty_base": 454, "unit_base": "g"}]}
    r = client.post("/alerts/shopping-list", json=body).json()
    assert r["text"] == "Reviri shopping list: Chicken Alfredo\n- Pasta, 454 g" and sent[-1][1] == r["text"]


def test_send_failure_is_a_readable_error(monkeypatch, sent):
    import notify

    async def broken(to, text):
        raise notify.NotifyError("Photon couldn't send the text: not signed in")

    monkeypatch.setattr(notify, "send_text", broken)
    client.put("/alerts", json={"phone": "5551234567", "enabled": False})
    r = client.post("/alerts/test")
    assert r.status_code == 502 and "not signed in" in r.json()["detail"]


# ---- rewind (Neon Time Travel replaced by a fixed "past")

def test_rewind_preview_and_restore(monkeypatch):
    import main
    import rewind
    from datetime import date
    from store import STAPLES
    import logic

    past_lots = [logic.make_lot(c, q, date.today()) for c, q in STAPLES]       # before the receipt scan
    asked = []

    async def fake_read_past(when):
        asked.append(when)
        return rewind.PastState(at=when, inventory=[l.model_copy() for l in past_lots],
                                totals={"grams_saved": 0.0, "dollars_saved": 0.0, "co2e_saved": 0.0,
                                        "wasted_g": 0.0, "skipped_days": 0})

    monkeypatch.setattr(rewind, "read_past", fake_read_past)
    monkeypatch.setattr(main.store, "db", object())             # pretend Neon is connected
    client.post("/demo-receipt")
    main.store.wasted_g = 500
    assert client.post("/checkin").json()["streak_days"] == 1

    p = client.get("/rewind/preview?minutes=15").json()
    assert p["minutes_ago"] == 15 and len(p["items"]) == 3
    chicken = next(c for c in p["changes"] if c["canonical"] == "chicken_breast")
    assert chicken["qty_then"] == 0 and chicken["qty_now"] == 680
    assert not any(c["canonical"] == "rice" for c in p["changes"])    # unchanged items aren't listed

    inv = client.post("/rewind", json={"at": p["at"]}).json()
    assert sorted(i["canonical"] for i in inv) == sorted(c for c, _ in STAPLES)
    assert asked[-1].isoformat().replace("+00:00", "Z") == p["at"]    # restored exactly the previewed moment
    stats = client.get("/stats").json()
    assert stats["wasted_g"] == 0 and stats["streak_days"] == 1      # totals rewound, streak kept


def test_rewind_rejects_bad_input_and_memory_mode(monkeypatch):
    import main
    assert client.get("/rewind/preview?minutes=0").status_code == 400
    assert client.get("/rewind/preview?minutes=361").status_code == 400
    assert client.post("/rewind", json={"at": "2020-01-01T00:00:00Z"}).status_code == 400
    assert client.post("/rewind", json={"at": "yesterday"}).status_code == 400
    monkeypatch.setattr(main.store, "db", None)
    r = client.get("/rewind/preview?minutes=5")
    assert r.status_code == 503 and "DATABASE_URL" in r.json()["detail"]
