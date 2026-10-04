"""App state. Lives in memory; with a Database (Neon) it's loaded at startup and
saved after every change (see db.py). Everything else only talks to the Store
through these attributes and methods."""
import json
from datetime import date, timedelta
from pathlib import Path
from typing import TYPE_CHECKING, Dict, List, Optional

import catalog
import logic
from models import InventoryItem, Recipe, Stats

if TYPE_CHECKING:
    from db import Database

_DATA = Path(__file__).parent / "data"

# What every kitchen "already has" at the start of the demo.
STAPLES = [("olive_oil", 500), ("soy_sauce", 296), ("rice", 907)]


class Store:
    def __init__(self, db: Optional["Database"] = None) -> None:
        with open(_DATA / "recipes.json") as f:
            self.recipes: List[Recipe] = [Recipe(**r) for r in json.load(f)]
        # Recipes Gemini wrote for searches, keyed by slug ("chicken-alfredo").
        # Kept separate from the recipe book, so suggestions and the waste forecast
        # only ever use the fixed book. Survives reset() so repeat searches stay instant.
        self.generated: Dict[str, Recipe] = {}
        # Text alerts (Photon). Also kept through reset(): it's a setting, not demo data.
        self.alert_phone: Optional[str] = None
        self.alerts_enabled = False
        self.last_alert_day: Optional[date] = None
        self.reset()
        self.db = db
        if db is not None:
            db.setup()
            if not db.load(self):      # a brand-new database: start it with the demo staples
                db.save(self)

    def save(self) -> None:
        """Persist everything (no-op without a database)."""
        if self.db is not None:
            self.db.save(self)

    def reset(self) -> None:
        today = date.today()
        self.inventory: List[InventoryItem] = [logic.make_lot(c, q, today) for c, q in STAPLES]
        self.grams_saved = 0.0
        self.dollars_saved = 0.0
        self.co2e_saved = 0.0
        self.wasted_g = 0.0
        self.skipped_days = 0          # demo: how far the pantry has been aged (see age())
        self.streak_days = 0
        self.last_checkin: Optional[date] = None

    def all_recipes(self) -> List[Recipe]:
        return self.recipes + list(self.generated.values())

    def recipe(self, recipe_id: str) -> Optional[Recipe]:
        for r in self.all_recipes():
            if r.id == recipe_id:
                return r
        return None

    def add_saved(self, grams: float, dollars: float, co2e: float) -> None:
        self.grams_saved += grams
        self.dollars_saved += dollars
        self.co2e_saved += co2e

    def remove(self, item_id: str, tossed: bool) -> bool:
        """Take a lot out of the pantry. tossed=True records it as wasted (the streak is not
        touched: being honest about waste should never cost you). Returns False if not found."""
        for lot in self.inventory:
            if lot.id == item_id:
                if tossed:
                    self.wasted_g += catalog.grams_equiv(lot.canonical, lot.qty_base)
                self.inventory = [l for l in self.inventory if l.id != item_id]
                return True
        return False

    def age(self, days: int) -> None:
        """Demo helper: make every pantry item `days` older, so perishables expire on stage.
        Moves purchase dates, not the clock, so the streak's real dates are untouched.
        Negative days undo a skip, but never past where we started."""
        days = max(days, -self.skipped_days)
        self.skipped_days += days
        for lot in self.inventory:
            lot.purchased_on = (date.fromisoformat(lot.purchased_on) - timedelta(days=days)).isoformat()

    def expired(self, today: date) -> List[InventoryItem]:
        """Lots past their date that the user hasn't dealt with yet (used or thrown away)."""
        return [l for l in self.inventory if l.qty_base > logic.EPS and logic.days_left(l, today) < 0]

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
            wasted_g=round(self.wasted_g, 1),
            expired=sorted({l.display_name for l in self.expired(today)}),
        )
