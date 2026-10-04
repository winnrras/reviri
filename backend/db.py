"""Neon (Postgres) persistence for the Store.

Set DATABASE_URL (Neon's connection string) in the server's environment to use it;
without it the server keeps everything in memory, as before.

How it works: the Store keeps working on in-memory objects, and after every request
that changed something, save() writes the whole state in ONE transaction (one user,
a few dozen rows). load() reads it back at startup, so restarts lose nothing.
The pantry is a real table (inventory_lots), one row per lot, which is what lets
Neon Time Travel read the pantry as it was at an earlier moment.
"""
import json
from datetime import date
from typing import TYPE_CHECKING, Callable, Optional, TypeVar

import psycopg
from psycopg.rows import dict_row

from models import InventoryItem, Recipe

if TYPE_CHECKING:
    from store import Store

T = TypeVar("T")

SCHEMA = """
create table if not exists inventory_lots (
    id              text primary key,
    canonical       text not null,
    display_name    text not null,
    qty_base        double precision not null,
    unit_base       text not null,
    category        text not null,
    purchased_on    date not null,
    shelf_life_days integer not null,
    brand           text
);
create table if not exists app_state (
    id              integer primary key default 1 check (id = 1),   -- exactly one row
    grams_saved     double precision not null default 0,
    dollars_saved   double precision not null default 0,
    co2e_saved      double precision not null default 0,
    wasted_g        double precision not null default 0,
    streak_days     integer not null default 0,
    last_checkin    date,
    skipped_days    integer not null default 0,
    alert_phone     text,
    alerts_enabled  boolean not null default false,
    last_alert_day  date,
    updated_at      timestamptz not null default now()
);
create table if not exists generated_recipes (
    slug            text primary key,
    recipe          jsonb not null,
    created_at      timestamptz not null default now()
);
"""

LOT_COLUMNS = ["id", "canonical", "display_name", "qty_base", "unit_base", "category",
               "purchased_on", "shelf_life_days", "brand"]
STATE_FIELDS = ["grams_saved", "dollars_saved", "co2e_saved", "wasted_g", "streak_days", "last_checkin",
                "skipped_days", "alert_phone", "alerts_enabled", "last_alert_day"]


def lot_from_row(row: dict) -> InventoryItem:
    return InventoryItem(**{**{k: row[k] for k in LOT_COLUMNS}, "purchased_on": row["purchased_on"].isoformat()})


class Database:
    def __init__(self, url: str) -> None:
        self.url = url
        self.conn: Optional[psycopg.Connection] = None

    def _run(self, work: Callable[[psycopg.Connection], T]) -> T:
        """Run `work` in a transaction. Neon suspends idle computes and drops their
        connections, so a dead connection is reopened once and the work retried."""
        for attempt in (1, 2):
            try:
                if self.conn is None or self.conn.closed:
                    self.conn = psycopg.connect(self.url, row_factory=dict_row, connect_timeout=15)
                with self.conn.transaction():
                    return work(self.conn)
            except psycopg.OperationalError:
                if self.conn is not None:
                    self.conn.close()
                self.conn = None
                if attempt == 2:
                    raise
        raise AssertionError("unreachable")

    def setup(self) -> None:
        self._run(lambda c: c.execute(SCHEMA))

    def load(self, store: "Store") -> bool:
        """Fill `store` from the database. False if the database is new (nothing saved yet)."""
        def work(c: psycopg.Connection) -> bool:
            state = c.execute("select * from app_state where id = 1").fetchone()
            if state is None:
                return False
            for field in STATE_FIELDS:
                setattr(store, field, state[field])
            store.inventory = [lot_from_row(r) for r in c.execute("select * from inventory_lots order by id")]
            store.generated = {r["slug"]: Recipe(**r["recipe"])
                               for r in c.execute("select slug, recipe from generated_recipes")}
            return True
        return self._run(work)

    def save(self, store: "Store") -> None:
        """Write the whole state in one transaction (all or nothing)."""
        def work(c: psycopg.Connection) -> None:
            c.execute("delete from inventory_lots")
            with c.cursor() as cur:
                cur.executemany(
                    "insert into inventory_lots (%s) values (%s)"
                    % (", ".join(LOT_COLUMNS), ", ".join(["%s"] * len(LOT_COLUMNS))),
                    [[getattr(lot, k) if k != "purchased_on" else date.fromisoformat(lot.purchased_on)
                      for k in LOT_COLUMNS] for lot in store.inventory])
                cur.executemany(
                    "insert into generated_recipes (slug, recipe) values (%s, %s) on conflict (slug) do nothing",
                    [(slug, json.dumps(r.model_dump())) for slug, r in store.generated.items()])
            c.execute(
                "insert into app_state (id, %s, updated_at) values (1, %s, now()) "
                "on conflict (id) do update set %s, updated_at = now()"
                % (", ".join(STATE_FIELDS), ", ".join(["%s"] * len(STATE_FIELDS)),
                   ", ".join("%s = excluded.%s" % (f, f) for f in STATE_FIELDS)),
                [getattr(store, f) for f in STATE_FIELDS])
        self._run(work)
