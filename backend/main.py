"""Reviri API.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
Docs: http://localhost:8000/docs  (try every endpoint in the browser)
"""
from datetime import date
from typing import List

import httpx
from fastapi import FastAPI, File, HTTPException, UploadFile

import logic
import receipt
from models import (
    CookRequest, CookResponse, InventoryItem, NextWeekRequest, NextWeekResponse, OK,
    PlanRequest, PlanResult, Recipe, Stats, SuggestionsResponse,
)
from store import Store

app = FastAPI(title="Reviri API")
store = Store()


def _inventory_view() -> List[InventoryItem]:
    today = date.today()
    items = [i.model_copy(update={"days_left": logic.days_left(i, today)})
             for i in store.inventory if i.qty_base > logic.EPS]
    return sorted(items, key=lambda i: (i.days_left, i.display_name))


def _recipe_or_404(recipe_id: str) -> Recipe:
    r = store.recipe(recipe_id)
    if r is None:
        raise HTTPException(404, "Unknown recipe: %s" % recipe_id)
    return r


@app.get("/health")
def health() -> dict:
    return {"ok": True, "gemini_key_set": receipt.has_api_key()}


@app.get("/recipes", response_model=List[Recipe])
def recipes():
    return store.recipes


@app.get("/inventory", response_model=List[InventoryItem])
def inventory():
    return _inventory_view()


@app.post("/parse-receipt", response_model=List[InventoryItem])
async def parse_receipt(file: UploadFile = File(...)):
    """Upload a receipt photo (multipart field name: file). Parsed items are added to the pantry."""
    data = await file.read()
    today = date.today()
    try:
        items = await receipt.parse_receipt(data, file.content_type or "image/jpeg", today)
    except httpx.HTTPError as e:
        raise HTTPException(502, "Gemini request failed: %s" % e)
    except (ValueError, KeyError, IndexError) as e:
        raise HTTPException(502, "Could not read Gemini's answer: %s" % e)
    store.inventory.extend(items)
    ids = {i.id for i in items}
    return [i for i in _inventory_view() if i.id in ids]


@app.post("/demo-receipt", response_model=List[InventoryItem])
def demo_receipt():
    """Adds a fixed sample receipt to the pantry. Works with no API key."""
    items = receipt.demo_items(date.today())
    store.inventory.extend(items)
    ids = {i.id for i in items}
    return [i for i in _inventory_view() if i.id in ids]


@app.put("/inventory/{item_id}", response_model=InventoryItem)
def update_item(item_id: str, body: InventoryItem):
    """Fix a quantity after a bad scan. Only qty_base is applied; 0 removes the item."""
    for lot in store.inventory:
        if lot.id == item_id:
            if body.qty_base < 0:
                raise HTTPException(400, "Quantity can't be negative")
            lot.qty_base = body.qty_base
            view = [i for i in _inventory_view() if i.id == item_id]
            return view[0] if view else lot.model_copy(update={"days_left": 0})
    raise HTTPException(404, "No such item")


@app.delete("/inventory/{item_id}", response_model=OK)
def delete_item(item_id: str):
    before = len(store.inventory)
    store.inventory = [i for i in store.inventory if i.id != item_id]
    if len(store.inventory) == before:
        raise HTTPException(404, "No such item")
    return OK()


@app.post("/plan", response_model=PlanResult)
def plan(req: PlanRequest):
    """Preview leftovers and missing items for a set of meals. Nothing is saved."""
    meals = [(_recipe_or_404(p.recipe_id), p.servings) for p in req.picks if p.servings > 0]
    return logic.preview(store.inventory, meals, date.today())


@app.post("/cook", response_model=CookResponse)
def cook(req: CookRequest):
    """Commit a meal: deduct ingredients. from_suggestion=true also counts the rescued food in stats."""
    recipe = _recipe_or_404(req.recipe_id)
    if req.servings <= 0:
        raise HTTPException(400, "servings must be positive")
    today = date.today()
    out = logic.cook(store.inventory, recipe, req.servings, req.from_suggestion, today)
    store.inventory = out.lots
    store.add_saved(out.saved_g, out.saved_usd, out.saved_co2e)
    return CookResponse(
        leftovers=logic.leftovers_for(store.inventory, out.touched, today),
        stats=store.stats(today),
    )


@app.get("/suggestions", response_model=SuggestionsResponse)
def suggestions():
    """Recipes that use up perishables we already own, best first."""
    return SuggestionsResponse(
        suggestions=logic.suggest(store.inventory, store.recipes, date.today()))


@app.post("/next-week", response_model=NextWeekResponse)
def next_week(req: NextWeekRequest):
    """Plan the next N meals around what's already here and build the shopping list."""
    meals, shopping, projected, baseline = logic.plan_week(
        store.inventory, store.recipes, req.meals, date.today())
    return NextWeekResponse(meals=meals, shopping_list=shopping,
                            projected_waste_g=projected, baseline_waste_g=baseline)


@app.get("/stats", response_model=Stats)
def stats():
    return store.stats(date.today())


@app.post("/checkin", response_model=Stats)
def checkin():
    """Streak: 'I wasted nothing today'. Once per day."""
    today = date.today()
    store.check_in(today)
    return store.stats(today)


@app.post("/reset", response_model=OK)
def reset():
    """Back to the starting pantry. Use before every demo run."""
    store.reset()
    return OK()
