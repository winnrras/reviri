"""Deploy the daily-alert Neon Function and its 9 AM schedule. Safe to run again.

    cd backend && .venv/bin/python neon/deploy.py

Reads keys from backend/.env (NEON_API_KEY, NEON_PROJECT_ID, SPECTRUM_PROJECT_ID,
SPECTRUM_PROJECT_SECRET). Creates NEON_ALERT_TOKEN in .env on first run; the server
uses it (with NEON_ALERT_URL, also written to .env) for "Send test alert".
"""
import json
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv, set_key

BACKEND = Path(__file__).resolve().parent.parent
ENV_FILE = BACKEND / ".env"
NEONCTL = BACKEND / "notify" / "node_modules" / ".bin" / "neonctl"
ESBUILD = BACKEND / "notify" / "node_modules" / ".bin" / "esbuild"
SRC = BACKEND / "neon" / "daily-alert" / "index.mjs"
BUNDLE = BACKEND / "neon" / "daily-alert" / "dist" / "index.mjs"
SLUG = "dailyalert"   # Neon: 1-20 lowercase letters and digits
TRIGGER = "reviri-daily-alert"
CRON = "0 13 * * *"        # 13:00 UTC = 9 AM in New York (EDT)


def neonctl(*args: str) -> str:
    cmd = [str(NEONCTL), *args, "--project-id", os.environ["NEON_PROJECT_ID"], "--output", "json"]
    p = subprocess.run(cmd, capture_output=True, text=True, env=dict(os.environ), timeout=300)
    if p.returncode != 0:
        sys.exit("neonctl %s failed:\n%s" % (args[0:2], (p.stderr or p.stdout)[-1500:]))
    return p.stdout


def build() -> None:
    """Bundle the function ourselves instead of letting neonctl do it.

    Photon's SDK checks that its gRPC packages exist as files (import.meta.resolve)
    before connecting. In a one-file bundle there is no node_modules, so that check
    fails even though the code is inside the bundle. The SDK skips the check when
    resolve isn't available, so we switch it off in the bundled output."""
    subprocess.run([str(ESBUILD), str(SRC), "--bundle", "--platform=node", "--format=esm", "--target=node24",
                    # CommonJS packages (pg, grpc) call require(); give the ESM bundle one.
                    "--banner:js=import { createRequire as __cr } from 'module'; const require = __cr(import.meta.url);",
                    "--outfile=" + str(BUNDLE), "--log-level=warning"], check=True)
    code = BUNDLE.read_text()
    code, n = re.subn(r'(function assertPeersResolvable\(\) \{\s*const (\w+) = import\.meta;\s*if \()'
                      r'typeof \2\.resolve !== "function"(\))', r"\1true\3", code)
    if n != 1:
        sys.exit("Couldn't find Photon's package check in the bundle (found %d). The SDK changed; "
                 "look for assertPeersResolvable in dist/index.mjs." % n)
    BUNDLE.write_text(code)
    print("Bundled %s (%.1f MB)" % (BUNDLE.relative_to(BACKEND), BUNDLE.stat().st_size / 1e6))


def main() -> None:
    load_dotenv(ENV_FILE)
    for key in ("NEON_API_KEY", "NEON_PROJECT_ID", "SPECTRUM_PROJECT_ID", "SPECTRUM_PROJECT_SECRET"):
        if not os.getenv(key):
            sys.exit("Missing %s in backend/.env" % key)
    token = os.getenv("NEON_ALERT_TOKEN")
    if not token:
        token = secrets.token_urlsafe(24)
        set_key(str(ENV_FILE), "NEON_ALERT_TOKEN", token, quote_mode="never")
        print("Created NEON_ALERT_TOKEN in backend/.env")

    build()
    print("Deploying function %r (this can take a minute)..." % SLUG)
    neonctl("functions", "deploy", SLUG, "--src", str(BUNDLE), "--no-bundle", "--wait",
            "--env", "SPECTRUM_PROJECT_ID=" + os.environ["SPECTRUM_PROJECT_ID"],
            "--env", "SPECTRUM_PROJECT_SECRET=" + os.environ["SPECTRUM_PROJECT_SECRET"],
            "--env", "ALERT_TOKEN=" + token,
            "--env", "ALERT_TIMEZONE=America/New_York")

    info = json.loads(neonctl("functions", "get", SLUG))
    url = next((v for k, v in _walk(info) if k in ("url", "invoke_url", "invocation_url") and str(v).startswith("https")), None)
    if url:
        set_key(str(ENV_FILE), "NEON_ALERT_URL", url, quote_mode="never")
        print("Function URL saved to backend/.env as NEON_ALERT_URL")
    else:
        print("Deployed, but couldn't find the function URL in:", json.dumps(info)[:800])

    triggers = json.loads(neonctl("triggers", "list"))
    if TRIGGER in json.dumps(triggers):
        print("Schedule %r already exists." % TRIGGER)
    else:
        neonctl("triggers", "create", "--function-slug", SLUG, "--name", TRIGGER, "--cron", CRON)
        print("Schedule created: every day at 9 AM New York time (%s UTC)." % CRON)
    print("Done. Restart the Reviri server so it picks up the new .env values.")


def _walk(obj, key=None):
    """Yield (key, value) for every scalar in nested JSON, to find the URL whatever the shape."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from _walk(v, k)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk(v, key)
    else:
        yield key, obj


if __name__ == "__main__":
    main()
