"""Text alerts through Photon Spectrum (iMessage).

Spectrum's SDK is TypeScript, so the actual send is done by notify/send.mjs (Node).
This file writes the messages and runs that script. Setup, once:  cd backend/notify && npm install

Mode: with SPECTRUM_PROJECT_ID and SPECTRUM_PROJECT_SECRET exported in the server's
terminal, texts go through Spectrum cloud (Photon's number). Without them, Spectrum's
local mode sends from this Mac's Messages app (the Mac must be signed into iMessage).
"""
import asyncio
import json
import os
import re
import shutil
from datetime import date
from pathlib import Path
from typing import List, Optional

import logic
from models import InventoryItem, ShoppingItem, Suggestion

NOTIFY_DIR = Path(__file__).parent / "notify"
SEND_TIMEOUT_S = 45


class NotifyError(Exception):
    """A text couldn't be sent; the message says why in plain words."""


def mode() -> str:
    return "cloud" if os.getenv("SPECTRUM_PROJECT_ID") and os.getenv("SPECTRUM_PROJECT_SECRET") else "local"


def normalize_phone(raw: str) -> Optional[str]:
    """"(555) 123-4567" -> "+15551234567". US numbers without a country code get +1.
    Returns None if it doesn't look like a phone number."""
    digits = re.sub(r"\D", "", raw or "")
    if (raw or "").strip().startswith("+"):
        phone = "+" + digits
    elif len(digits) == 10:
        phone = "+1" + digits
    elif len(digits) == 11 and digits.startswith("1"):
        phone = "+" + digits
    else:
        return None
    return phone if re.fullmatch(r"\+\d{8,15}", phone) else None


def qty_text(qty: float, unit: str) -> str:
    """Same format as the app: 680 g, 233 ml, 12 pcs."""
    rounded = round(qty) if qty >= 10 else round(qty, 1)
    number = str(int(rounded)) if rounded == int(rounded) else str(rounded)
    return "%s pcs" % number if unit == "count" else "%s %s" % (number, unit)


def spoil_alert_text(inventory: List[InventoryItem], suggestions: List[Suggestion], today: date) -> Optional[str]:
    """The daily alert: what must be used by tomorrow, plus the best recipe for it.
    None when nothing is close to spoiling."""
    soon = sorted((l for l in inventory if l.qty_base > logic.EPS and 0 <= logic.days_left(l, today) <= 1),
                  key=lambda l: (logic.days_left(l, today), l.display_name))
    if not soon:
        return None
    lines = ["Reviri: use these by tomorrow"]
    for lot in soon:
        when = "today" if logic.days_left(lot, today) == 0 else "tomorrow"
        lines.append("- %s, %s (spoils %s)" % (lot.display_name, qty_text(lot.qty_base, lot.unit_base), when))
    if suggestions:
        lines.append("Idea: %s. Open Next Up in Reviri for more." % suggestions[0].recipe.name)
    return "\n".join(lines)


def shopping_list_text(title: str, items: List[ShoppingItem]) -> str:
    lines = ["Reviri shopping list: %s" % title.strip()[:80]]
    lines += ["- %s, %s" % (i.display_name, qty_text(i.qty_base, i.unit_base)) for i in items]
    if not items:
        lines.append("Nothing to buy. You have everything.")
    return "\n".join(lines)


async def send_text(to: str, text: str) -> str:
    """Send one iMessage through Spectrum. Returns the mode used. Raises NotifyError."""
    node = shutil.which("node")
    if node is None:
        raise NotifyError("Node.js isn't installed on the server Mac, and Photon's SDK needs it.")
    if not (NOTIFY_DIR / "node_modules").exists():
        raise NotifyError("Photon's SDK isn't installed. Run: cd backend/notify && npm install")
    proc = await asyncio.create_subprocess_exec(
        node, "send.mjs", cwd=str(NOTIFY_DIR),
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(proc.communicate(json.dumps({"to": to, "text": text}).encode()),
                                          timeout=SEND_TIMEOUT_S)
    except asyncio.TimeoutError:
        proc.kill()
        raise NotifyError("Photon didn't finish sending within %d seconds." % SEND_TIMEOUT_S)
    # Spectrum logs to stdout too; our script's answer is the line starting with {"ok".
    result = None
    for line in out.decode(errors="replace").splitlines():
        if line.startswith('{"ok"'):
            result = json.loads(line)
    if result is None:
        raise NotifyError("Photon's sender crashed: %s" % err.decode(errors="replace").strip()[-300:])
    if not result.get("ok"):
        error = str(result.get("error"))
        if "Target not allowed" in error:
            # Free/Pro plans use shared lines that only text the project's registered users.
            raise NotifyError("Photon's free plan only texts numbers added as Users of your project. Add %s "
                              "under Users at app.photon.codes (or find your exact iMessage handle at "
                              "debug.photon.codes), then try again." % to)
        raise NotifyError("Photon couldn't send the text: %s" % error)
    print("[notify] sent to %s via Spectrum %s" % (to, result.get("mode")))
    return result.get("mode", "local")
