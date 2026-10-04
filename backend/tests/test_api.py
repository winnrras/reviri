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
