# Reviri (MHacks 26 starter)

Scan a grocery receipt, plan meals, see exactly what will be left over, and get suggestions that use it up before it spoils.

- `backend/` Python (FastAPI). All the math lives here and is tested: `pytest` should say **26 passed**.
- `ios/Reviri/` SwiftUI app (iOS 17+). Starts in **mock mode**, so it runs before the server does.

## 1. Run the backend (Terminal on your Mac)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pytest                      # sanity check
export GEMINI_API_KEY=your-key-from-aistudio.google.com   # optional
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Open http://localhost:8000/docs and click through every endpoint in the browser.
Without `GEMINI_API_KEY`, "scan receipt" returns the built-in demo receipt, so the whole flow works with no key.
Run `source .venv/bin/activate` again in every new Terminal window before `uvicorn`.

## 2. Create the Xcode project

1. Xcode > File > New > Project > **iOS > App**. Product Name `Reviri`, Interface **SwiftUI**, Language **Swift**, Testing System **None**, Storage **None**. Save it on your **Desktop** (not inside `ios/`, which already has a `Reviri` folder). Move the finished Xcode project next to `backend/` later if you want it in git.
2. In the left sidebar, **delete** the `ReviriApp.swift` and `ContentView.swift` Xcode made (Move to Trash).
3. Drag every `.swift` file from `ios/Reviri/` into the Xcode sidebar. Tick **Copy items if needed** and make sure the **Reviri target** box is checked.
4. Click the blue project icon > target **Reviri** > **General**: set the minimum iOS deployment to **17.0**.
5. Same screen, **Info** tab > add three rows (hover a row, click +):
   - `Privacy - Camera Usage Description` = `Scan grocery receipts`
   - `Privacy - Local Network Usage Description` = `Connect to the Reviri server`
   - `App Transport Security Settings` > add child `Allow Arbitrary Loads` = `YES` (lets the app use plain `http://` to your Mac)
6. Press **Cmd+R**. In the Simulator you get the full app on mock data. The camera doesn't exist there; use "Use demo receipt" or "Choose from Photos".

Only one person should do steps 1 to 5. Everyone else pulls the project from git. Don't edit the same Swift file at the same time, and avoid touching project settings after setup (the `.xcodeproj` file conflicts easily).

## 3. Run on a real iPhone (needed for the camera scanner)

1. Plug in the iPhone. On the phone: Settings > Privacy & Security > **Developer Mode** > on (it restarts).
2. Xcode > target > **Signing & Capabilities** > tick *Automatically manage signing*, pick your personal Apple ID as Team. Change the Bundle Identifier to something unique, like `com.yourname.reviri`.
3. Pick your iPhone at the top of Xcode and press **Cmd+R**. Do this once early. Free signing expires after 7 days.
4. First launch: Settings > General > VPN & Device Management > trust your Apple ID.

## 4. Connect the app to the server

In the app: **Scan tab > gear icon > Settings**. Turn off *Use mock data* and set the server address to `http://<your-mac-ip>:8000`.
Get the IP with `ipconfig getifaddr en0` in Terminal. Phone and Mac must be on the same network.

Hackathon wifi often blocks devices from talking to each other. If the app can't reach the server:
- Turn on **Personal Hotspot** on the iPhone, join it from the Mac, and use the Mac's new IP; or
- Use mock mode for the demo (it's the safety net), or
- Deploy `backend/` to a host such as Render or Railway and use its `https://` address.

## 5. Demo script (about 2 minutes)

1. Settings > **Reset demo data**.
2. **Scan** > scan a real receipt (or "Use demo receipt").
3. **Plan** > Add *Creamy Spinach Chicken*. Leftover cream and spinach appear live. Tap **I cooked these**.
4. **Next Up** > top suggestion is *Spinach & Mushroom Quiche*, "Nothing extra to buy". Tap **Cook this**: "You rescued 370 g".
5. **Next Up > Plan ahead**: meals, shopping list, and the waste forecast vs. a random plan.
6. **Savings**: food, money, CO2e, tap the streak check-in.

## API (differences from the earlier draft)

| Endpoint | Notes |
|---|---|
| `POST /parse-receipt` | multipart field `file`; adds parsed items to the pantry |
| `POST /demo-receipt` | fixed sample receipt, no API key needed |
| `GET /inventory`, `PUT /inventory/{id}`, `DELETE /inventory/{id}` | edit or remove a bad scan line |
| `GET /recipes` | the recipe book |
| `POST /plan` body `{picks:[{recipe_id, servings}]}` | preview only, saves nothing |
| `POST /cook` | commits a meal; `from_suggestion: true` counts rescued food in stats |
| `GET /suggestions` | richer than the draft: `{suggestions:[{recipe, reason, rescued, missing, score}]}` |
| `POST /next-week` body `{meals: n}` | replaces `/shopping-list`; returns meals, `shopping_list`, `projected_waste_g`, `baseline_waste_g` |
| `GET /stats`, `POST /checkin`, `POST /reset` | `checked_in_today` added to stats |

## How the planner works (your pitch)

- **No LLM does arithmetic.** Gemini only reads the receipt and maps each line to a fixed ingredient list (`backend/data/canonical.json`). All quantities come from `logic.py`.
- Cooking takes from the lot that spoils soonest. Missing food is "bought" in whole packages, and the unused part of a package becomes leftover stock that later recipes can use.
- Each recipe is scored: reward for using up perishables (weighted by how soon they spoil), penalty for each ingredient you'd have to buy (`MISSING_PENALTY` in `logic.py`). The planner picks the best one, updates the stock, and repeats.
- The waste forecast compares that plan to the average of 200 random plans from the same recipe book. Say exactly that to judges; don't call it a real-world measurement.

## Where to change things

- Add recipes: `backend/data/recipes.json` (use keys from `canonical.json`; a test checks this).
- Add ingredients, pack sizes, shelf lives, prices: `backend/data/canonical.json`.
- Make suggestions pickier or looser: `MISSING_PENALTY`, `MAX_MISSING_FOR_SUGGESTION` in `logic.py`.
- Persist data (Neon/Postgres): replace `backend/store.py`; nothing else touches storage.

## Known gaps

- **The Swift code has not been compiled.** It was written without Xcode. If Xcode shows red errors, paste the exact message to Claude.
- **The Gemini call is untested** (no API key where this was written). Check the model name in `receipt.py` (`GEMINI_MODEL`) against Google AI Studio, and try 3 real receipts early.
- Shelf lives, prices and CO2e factors are rough placeholders. Replace them with sourced numbers (for example USDA FoodKeeper for shelf life) before you quote them to judges.
- State is in memory: restarting the server resets it.
- Only the first page of a multi-page scan is sent.
