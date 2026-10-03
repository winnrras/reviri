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
