"""API shapes. The Swift structs in ios/Reviri/Models.swift mirror these one-to-one."""
from typing import List, Optional

from pydantic import BaseModel


class IngredientQty(BaseModel):
    canonical: str
    qty_base: float
    unit_base: str


class Recipe(BaseModel):
    id: str
    name: str
    servings: int
    ingredients: List[IngredientQty]       # tracked: these move the pantry math
    steps: List[str] = []                  # cooking steps (only generated recipes have them)
    untracked: List[str] = []              # ingredients outside our catalog, e.g. "1 tsp paprika"
    generated: bool = False                # True = written by Gemini from a search


class InventoryItem(BaseModel):
    id: str
    canonical: str
    display_name: str
    qty_base: float
    unit_base: str
    category: str
    purchased_on: str          # ISO date, e.g. "2026-10-03"
    shelf_life_days: int
    days_left: Optional[int] = None   # filled in by the server


class MealPick(BaseModel):
    recipe_id: str
    servings: int


class Leftover(BaseModel):
    canonical: str
    display_name: str
    qty_base: float
    unit_base: str
    days_until_spoil: int


class ShoppingItem(BaseModel):
    canonical: str
    display_name: str
    qty_base: float
    unit_base: str


class PlanRequest(BaseModel):
    picks: List[MealPick]


class PlanResult(BaseModel):
    leftovers: List[Leftover]
    missing: List[ShoppingItem]


class Stats(BaseModel):
    grams_saved: float
    dollars_saved: float
    co2e_saved: float
    streak_days: int
    checked_in_today: bool


class CookRequest(BaseModel):
    recipe_id: str
    servings: int
    from_suggestion: bool = False


class CookResponse(BaseModel):
    leftovers: List[Leftover]
    stats: Stats


class Suggestion(BaseModel):
    recipe: Recipe
    reason: str
    rescued: List[str]
    missing: List[ShoppingItem]
    score: float


class GenerateRecipeRequest(BaseModel):
    name: str                  # what the user typed, e.g. "chicken alfredo"


class SuggestionsResponse(BaseModel):
    suggestions: List[Suggestion]


class PlannedMeal(BaseModel):
    recipe: Recipe
    servings: int
    reason: str


class NextWeekRequest(BaseModel):
    meals: int = 4


class NextWeekResponse(BaseModel):
    meals: List[PlannedMeal]
    shopping_list: List[ShoppingItem]
    projected_waste_g: float    # perishables left over at the end of OUR plan
    baseline_waste_g: float     # average for random plans from the same recipe book


class OK(BaseModel):
    ok: bool = True
