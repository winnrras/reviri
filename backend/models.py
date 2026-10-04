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
    brand: Optional[str] = None       # e.g. "Kikkoman", read from a receipt or fridge photo


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
    wasted_g: float = 0.0             # food marked "threw it away" (never resets the streak)
    expired: List[str] = []           # names of pantry items past their date; they block check-in


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


class FridgeItem(BaseModel):
    """One thing seen in a fridge photo, proposed as a pantry change. Nothing is saved yet."""
    label: str                     # what Gemini saw, e.g. "Fat free skim milk, 1 gallon"
    canonical: Optional[str]       # None = not something Reviri tracks
    display_name: str
    qty_base: float                # estimated amount now (0 for untracked)
    unit_base: str
    action: str                    # "update" (already in pantry), "add" (new) or "untracked"
    pantry_qty: float              # what the pantry holds now (0 for add/untracked)
    estimate: str                  # how the amount was worked out, e.g. "1 container, about half full"
    brand: Optional[str] = None    # brand read on the package, if any


class FridgeScanResponse(BaseModel):
    items: List[FridgeItem]


class FridgeApplyItem(BaseModel):
    canonical: str
    qty_base: float                # the amount the user confirmed
    brand: Optional[str] = None


class FridgeApplyRequest(BaseModel):
    items: List[FridgeApplyItem]


class AlertSettings(BaseModel):
    """Text alerts through Photon (iMessage). Kept across demo resets."""
    phone: Optional[str] = None    # E.164, e.g. "+15551234567"
    enabled: bool = False          # daily "spoils by tomorrow" alert
    mode: str = "local"            # "local" (this Mac's Messages) or "cloud" (Spectrum keys set); read-only


class ShoppingListRequest(BaseModel):
    title: str                     # e.g. "Creamy Spinach Chicken" or "This week's plan"
    items: List[ShoppingItem]


class AlertSent(BaseModel):
    ok: bool = True
    text: str                      # exactly what was sent, so the app can show it


class RewindChange(BaseModel):
    """One ingredient whose amount differs between the past moment and now."""
    canonical: str
    display_name: str
    unit_base: str
    qty_then: float
    qty_now: float


class RewindPreview(BaseModel):
    at: str                        # the past moment (UTC, ISO 8601); send it back to restore exactly this
    minutes_ago: int
    items: List[InventoryItem]     # the pantry as it was then (days_left as of today)
    changes: List[RewindChange]    # what restoring would change, by ingredient


class RewindRequest(BaseModel):
    at: str                        # from a preview
