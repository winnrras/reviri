"""In-memory state. For persistence, swap this one file for Neon/Postgres.
Everything else only talks to the Store through these attributes and methods."""
import json
from datetime import date, timedelta
from pathlib import Path
from typing import List, Optional

import logic
from models import InventoryItem, Recipe, Stats

_DATA = Path(__file__).parent / "data"

# What every kitchen "already has" at the start of the demo.
STAPLES = [("olive_oil", 500), ("soy_sauce", 296), ("rice", 907)]


class Store:
    def __init__(self) -> None:
        with open(_DATA / "recipes.json") as f:
            self.recipes: List[Recipe] = [Recipe(**r) for r in json.load(f)]
        self.reset()

    def reset(self) -> None:
        today = date.today()
        self.inventory: List[InventoryItem] = [logic.make_lot(c, q, today) for c, q in STAPLES]
        self.grams_saved = 0.0
        self.dollars_saved = 0.0
        self.co2e_saved = 0.0
        self.streak_days = 0
        self.last_checkin: Optional[date] = None

    def recipe(self, recipe_id: str) -> Optional[Recipe]:
        for r in self.recipes:
            if r.id == recipe_id:
                return r
        return None

    def add_saved(self, grams: float, dollars: float, co2e: float) -> None:
        self.grams_saved += grams
        self.dollars_saved += dollars
        self.co2e_saved += co2e

    def check_in(self, today: date) -> None:
        if self.last_checkin == today:
            return
        if self.last_checkin == today - timedelta(days=1):
            self.streak_days += 1
        else:
            self.streak_days = 1
        self.last_checkin = today

    def stats(self, today: date) -> Stats:
        return Stats(
            grams_saved=round(self.grams_saved, 1),
            dollars_saved=round(self.dollars_saved, 2),
            co2e_saved=round(self.co2e_saved, 2),
            streak_days=self.streak_days,
            checked_in_today=(self.last_checkin == today),
        )
