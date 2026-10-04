# Its presence makes pytest put this folder on sys.path so tests can `import logic`.
import os

# Tests must never touch the real (Neon) database, even if DATABASE_URL is exported
# in this terminal. The Postgres tests start their own throwaway server instead.
os.environ.pop("DATABASE_URL", None)
os.environ["REVIRI_TESTING"] = "1"          # main.py then skips loading backend/.env
