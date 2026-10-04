"""Persistence against a real Postgres (a throwaway local server, same SQL as Neon)."""
import tempfile
from datetime import date

import pytest

pgserver = pytest.importorskip("pgserver")

import db
import main
import receipt
from fastapi.testclient import TestClient
from models import Recipe
from store import Store


@pytest.fixture(scope="module")
def pg_url():
    server = pgserver.get_server(tempfile.mkdtemp(), cleanup_mode="stop")
    yield server.get_uri()
    server.cleanup()


@pytest.fixture
def database(pg_url):
    d = db.Database(pg_url)
    d.setup()
    d._run(lambda c: c.execute("truncate inventory_lots, app_state, generated_recipes"))
    return d


def test_new_database_starts_with_the_staples(database):
    store = Store(database)
    again = Store(database)                      # a "restart"
    assert sorted(l.canonical for l in again.inventory) == sorted(l.canonical for l in store.inventory)
    assert {l.id for l in again.inventory} == {l.id for l in store.inventory}


def test_everything_survives_a_restart(database):
    store = Store(database)
    store.inventory += receipt.demo_items(date.today())
    store.inventory[0].brand = "Kikkoman"
    store.add_saved(370, 3.1, 0.9)
    store.wasted_g = 283
    store.check_in(date.today())
    store.alert_phone, store.alerts_enabled = "+15551234567", True
    store.generated["chicken-alfredo"] = Recipe(id="gen-chicken-alfredo", name="Chicken Alfredo", servings=4,
                                                ingredients=[], steps=["Cook."], generated=True)
    store.save()

    again = Store(database)
    assert [l.model_dump() for l in again.inventory] == [l.model_dump() for l in sorted(store.inventory, key=lambda l: l.id)]
    assert again.stats(date.today()) == store.stats(date.today())
    assert (again.alert_phone, again.alerts_enabled) == ("+15551234567", True)
    assert again.generated["chicken-alfredo"].steps == ["Cook."]


def test_removed_items_stay_removed(database):
    store = Store(database)
    gone = store.inventory[0].id
    store.remove(gone, tossed=True)
    store.save()
    assert gone not in {l.id for l in Store(database).inventory}


def test_api_saves_after_each_change(database, monkeypatch):
    monkeypatch.setattr(main, "store", Store(database))
    client = TestClient(main.app)
    client.post("/reset")
    client.post("/demo-receipt")
    assert client.get("/health").json()["database"] == "neon"
    restarted = Store(database)
    assert len(restarted.inventory) == len(main.store.inventory) == 13   # 3 staples + 10 receipt lines


def test_reconnects_after_the_connection_drops(database):
    store = Store(database)
    # Kill our own session from a second connection, like Neon suspending an idle compute.
    import psycopg
    pid = database.conn.info.backend_pid
    with psycopg.connect(database.url, autocommit=True) as other:
        other.execute("select pg_terminate_backend(%s)", [pid])
    store.wasted_g = 42
    store.save()                                  # must reconnect and succeed
    assert Store(database).wasted_g == 42
