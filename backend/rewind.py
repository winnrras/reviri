"""Rewind: see the pantry as it was up to 6 hours ago, and restore it.

Reviri keeps no history of its own. Neon Time Travel does it: neonctl asks Neon for a
connection to the database AS IT WAS at a past moment (a temporary, read-only copy,
gone 30 seconds after we stop using it). We read the pantry there, and restoring
writes it back to the present.

Needs DATABASE_URL (Neon), NEON_API_KEY and NEON_PROJECT_ID, and neonctl installed in
backend/notify (npm install). The Free plan keeps 6 hours of history.
"""
import asyncio
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import List, Optional
from urllib.parse import urlparse

import httpx
import psycopg
from psycopg.rows import dict_row

import db
from models import InventoryItem

NEONCTL = Path(__file__).parent / "notify" / "node_modules" / ".bin" / "neonctl"
MAX_MINUTES = 6 * 60          # Neon Free plan history window
NEONCTL_TIMEOUT_S = 60
_branch_name: Optional[str] = None     # the project's default branch, looked up once


class RewindError(Exception):
    """Rewind isn't possible right now; the message says why in plain words."""


@dataclass
class PastState:
    at: datetime
    inventory: List[InventoryItem]
    totals: dict                # grams_saved, dollars_saved, co2e_saved, wasted_g, skipped_days


def check_setup() -> None:
    missing = [k for k in ("DATABASE_URL", "NEON_API_KEY", "NEON_PROJECT_ID") if not os.getenv(k)]
    if missing:
        raise RewindError("Rewind needs Neon: add %s to backend/.env and restart the server." % ", ".join(missing))
    if not NEONCTL.exists():
        raise RewindError("Neon's CLI isn't installed. Run: cd backend/notify && npm install")


def moment(minutes_ago: int) -> datetime:
    if not 1 <= minutes_ago <= MAX_MINUTES:
        raise RewindError("Rewind goes back 1 minute to 6 hours.")
    return (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).replace(microsecond=0)


def parse_moment(at: str) -> datetime:
    """A moment previously returned by a preview; must still be inside the history window."""
    try:
        when = datetime.fromisoformat(at.replace("Z", "+00:00"))
    except ValueError:
        raise RewindError("That rewind time isn't valid.")
    now = datetime.now(timezone.utc)
    if when.tzinfo is None or not now - timedelta(minutes=MAX_MINUTES) < when < now:
        raise RewindError("That moment is outside the last 6 hours. Pick a newer one.")
    return when


async def _past_connection_string(when: datetime) -> str:
    """Ask Neon (via neonctl) for a connection to the default branch as of `when`."""
    proc = await asyncio.create_subprocess_exec(
        str(NEONCTL), "connection-string", "%s@%s" % (await _default_branch(), when.isoformat().replace("+00:00", "Z")),
        "--project-id", os.environ["NEON_PROJECT_ID"],
        "--database-name", urlparse(os.environ["DATABASE_URL"]).path.lstrip("/") or "neondb",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        env=dict(os.environ))        # neonctl reads NEON_API_KEY from here, never from the command line
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=NEONCTL_TIMEOUT_S)
    except asyncio.TimeoutError:
        proc.kill()
        raise RewindError("Neon took too long to open that moment. Try again.")
    url = out.decode().strip().splitlines()[-1] if out.strip() else ""
    if proc.returncode != 0 or not url.startswith("postgres"):
        raise RewindError("Neon couldn't open that moment: %s" % err.decode(errors="replace").strip()[-300:])
    return url


async def _default_branch() -> str:
    """Name of the project's default branch ("production" on new projects). Asked once."""
    global _branch_name
    if _branch_name is None:
        async with httpx.AsyncClient(timeout=20) as client:
            r = await client.get("https://console.neon.tech/api/v2/projects/%s/branches" % os.environ["NEON_PROJECT_ID"],
                                 headers={"Authorization": "Bearer " + os.environ["NEON_API_KEY"]})
        if r.status_code != 200:
            raise RewindError("Neon refused the API key or project ID (%d). Check backend/.env." % r.status_code)
        branches = r.json().get("branches", [])
        _branch_name = next((b["name"] for b in branches if b.get("default")), branches[0]["name"] if branches else "main")
    return _branch_name


def _read_past(url: str, when: datetime) -> PastState:
    try:
        with psycopg.connect(url, row_factory=dict_row, connect_timeout=30) as c:
            lots = [db.lot_from_row(r) for r in c.execute("select * from inventory_lots order by id")]
            state = c.execute("select grams_saved, dollars_saved, co2e_saved, wasted_g, skipped_days "
                              "from app_state where id = 1").fetchone()
    except psycopg.errors.UndefinedTable:
        raise RewindError("Reviri wasn't saving to Neon yet at that moment. Pick a newer one.")
    if state is None:
        raise RewindError("Reviri wasn't saving to Neon yet at that moment. Pick a newer one.")
    return PastState(at=when, inventory=lots, totals=dict(state))


async def read_past(when: datetime) -> PastState:
    check_setup()
    url = await _past_connection_string(when)
    return await asyncio.to_thread(_read_past, url, when)
