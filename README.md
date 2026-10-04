# Reviri

**Use it before you lose it.** Reviri is an iPhone app that stops food from going to waste at home. Scan a grocery receipt (or snap your fridge), and Reviri knows what you have and when it spoils. It turns what's about to go bad into your next meal, plans your week so leftovers get used, and texts you the morning something needs eating.

Built at **MHacks 26** (Sustainability track) in 30 hours.

Households cause 60% of the world's food waste ([UNEP Food Waste Index Report 2024](https://www.unep.org/resources/publication/food-waste-index-report-2024)). Most of it isn't a choice: food gets forgotten at the back of the fridge, or a recipe needs half a tub of cream and the rest goes off. Reviri fixes the forgetting and the half-tubs.

## What it does

| Feature | How it works |
| --- | --- |
| **Scan a receipt** | Gemini reads the photo and maps every line to a fixed ingredient list; Python does all the unit math. "ORG BNLS CHKN BRST 1.52 lb" becomes 689 g chicken breast with a 1-day shelf life. |
| **Scan your fridge** | Gemini sees what's in the photo, reads brands and estimates how full each container is. Items already in the pantry are *updated*, not added twice. You review every amount before saving. |
| **Plan with live leftovers** | Pick meals and servings; the leftovers (with spoil dates) update as you go. Missing food is bought in whole packages, and the unused part becomes stock later meals can use. |
| **Next Up** | Ranks recipes by how much about-to-spoil food they rescue, minus a penalty for each thing you'd have to buy. "Cook this" counts the rescued food on Savings. |
| **Plan ahead + waste forecast** | Plans N meals that share ingredients, builds the shopping list, and compares the leftover waste against the average of 200 random plans from the same recipe book. |
| **Recipe search** | Type any dish; Gemini writes the recipe, mapped onto the same ingredients, so it can be cooked and planned like any other. |
| **Rewind** | An undo for your pantry, up to 6 hours back, with zero history code: it's Neon Time Travel (see below). |
| **Text alerts** | Every morning at 9 AM, an iMessage lists what spoils by tomorrow. "Text me this list" sends any shopping list to your phone. Sent with Photon. |
| **Honest streak** | Check in daily once nothing in the pantry has expired. Logging food as "threw it away" is counted on Savings but never breaks the streak, so people stay honest. |
| **Savings** | Food rescued, money saved, CO2e avoided, food thrown away. |

## Sponsor technology

**Neon (Postgres + Time Travel + Functions)**
- **Postgres:** all state (pantry lots, stats, settings, generated recipes) is saved after every change in one transaction (`backend/db.py`) and survives restarts.
- **Time Travel, as a user feature:** Rewind asks Neon for a read-only connection to the database *as it was* at a past moment (`backend/rewind.py`). Neon spins up a temporary branch, we read the pantry, write it back to the present, and Neon deletes the branch 30 seconds later. Reviri stores no history of its own.
- **Functions + schedule triggers:** the 9 AM spoil alert runs as a Neon Function next to the data (`backend/neon/daily-alert/`), so it's sent even when the laptop and the API server are off.

**Photon (Spectrum, iMessage)**
- Daily spoil alerts and "Text me this list" go out over iMessage through Spectrum cloud (`backend/notify/send.mjs`, and inside the Neon Function). Local mode (the Mac's Messages app) works without an account.

**Google Gemini**
- Reads receipts and fridge photos and writes searched recipes. Gemini never does arithmetic: it only maps text to fixed ingredient keys, and every number is computed and tested in Python. Retries and model fallbacks keep the demo alive when a model is busy.

**Figma**
- The whole UI follows the team's Figma file: tokens (`ios/Reviri/Reviri/Theme.swift`), screens, and the illustrations exported as vectors.

## Where the numbers come from

- **Shelf lives:** USDA FoodKeeper (low end of each range).
- **Prices:** US Bureau of Labor Statistics average prices (Aug 2026) where a series exists; the rest are labelled estimates.
- **CO2e:** Poore & Nemecek (2018, *Science*), by food group.

Every value and its source is listed in [`backend/data/SOURCES.md`](backend/data/SOURCES.md). The waste forecast is a comparison against random plans from the same recipe book, not a real-world measurement.

## How it's built

```
iPhone app (SwiftUI)  ──HTTP──▶  FastAPI server (Python)  ──▶  Neon Postgres
                                   │   logic.py: all the math (tested)
                                   ├──▶ Gemini (receipts, fridge photos, recipes)
                                   └──▶ Photon Spectrum (iMessage)
Neon Function (Node, 9 AM schedule) ──▶ Neon Postgres + Photon Spectrum
```

- `backend/`: FastAPI, pydantic, psycopg. `logic.py` is pure, deterministic Python: inventory "lots" with purchase dates, soonest-to-spoil-first consumption, whole-package buying, recipe scoring, the 200-random-plan baseline. **59 tests** (`pytest`), including persistence against a real Postgres.
- `ios/Reviri/`: SwiftUI, iOS 17+, one `@Observable` app state, and a **mock mode** that runs every screen with no server (the demo backup).

## Run it

**Backend** (Python 3.9+, Node 20+):

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # then fill in your keys (never commit .env)
(cd notify && npm install)      # Photon sender + Neon CLI
pytest                          # 59 passed
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Every key is optional: without `GEMINI_API_KEY` the receipt scan returns a demo receipt, without `DATABASE_URL` state stays in memory, without Spectrum keys alerts go through the Mac's Messages app. API docs: http://localhost:8000/docs.

Deploy the 9 AM alert to Neon: `.venv/bin/python neon/deploy.py` (needs the Neon and Spectrum keys in `.env`).

**iPhone app:** open `ios/Reviri/Reviri.xcodeproj` in Xcode, choose your team and a unique bundle ID under Signing & Capabilities, and press ⌘R. The app starts in mock mode. To use the server: Scan tab > gear > turn off *Use mock data* and set the address to `http://<your-mac-ip>:8000` (`ipconfig getifaddr en0`).

## Known limits

- Single user; no accounts.
- Only the first page of a multi-page receipt scan is read.
- Fridge amounts are estimates from a photo, so the review sheet asks you to check them.
- Photon's free plan only texts numbers registered in the Photon project.
- Rewind reaches back 6 hours (Neon free plan history window).
