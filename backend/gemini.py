"""The one place that talks to the Gemini API. Gemini only reads and writes text;
every number the app shows is computed afterwards in Python.

Needs GEMINI_API_KEY in the server's environment (never in a file).
"""
import asyncio
import json
import os
import time
from typing import Any, Dict, List, Optional

import httpx

# Check Google AI Studio for the current model name and override with GEMINI_MODEL if needed.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
# Tried in order when the main model is overloaded (503) or rate limited (429).
GEMINI_FALLBACK_MODELS = os.getenv(
    "GEMINI_FALLBACK_MODELS", "gemini-3.5-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite").split(",")
RETRY_STATUSES = {429, 500, 503}
# Per-model wait, and the most we spend across all models (the app gives up at 120 s).
TIMEOUT_S = 40
DEADLINE_S = 100
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
GEMINI_LIST_URL = "https://generativelanguage.googleapis.com/v1beta/models"


def has_api_key() -> bool:
    return bool(os.getenv("GEMINI_API_KEY"))


def extract_json(text: str) -> Any:
    """Parse Gemini's answer, tolerating a ```json fence around it."""
    text = text.strip()
    if "```" in text:
        # Keep what's inside the first fence; Gemma sometimes adds a sentence around it.
        text = text.split("```")[1]
        if text.lower().startswith("json"):
            text = text[4:]
    return json.loads(text)


def _payload(parts: List[Dict[str, Any]], model: str) -> Dict[str, Any]:
    config: Dict[str, Any] = {"temperature": 0}
    if not model.startswith("gemma"):
        config["responseMimeType"] = "application/json"   # Gemma models don't support JSON mode
    return {"contents": [{"parts": parts}], "generationConfig": config}


async def generate_json(parts: List[Dict[str, Any]], label: str, model: Optional[str] = None) -> Any:
    """Send `parts` (text and/or inlineData) and return the parsed JSON answer.

    Raises ValueError with Google's explanation if every model fails.
    `label` only tags the server log lines (e.g. "receipt").
    `model` replaces the main model (e.g. a Gemma model); the fallbacks stay the same.
    """
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise ValueError("GEMINI_API_KEY is not set on the server")
    main = model or GEMINI_MODEL
    headers = {"x-goog-api-key": key}
    deadline = time.monotonic() + DEADLINE_S
    resp = None
    async with httpx.AsyncClient(timeout=TIMEOUT_S) as client:
        # Main model, one retry after a short wait, then each fallback model.
        attempts = [(main, 0), (main, 2)] + [(m.strip(), 0) for m in GEMINI_FALLBACK_MODELS]
        for model, wait in attempts:
            left = deadline - time.monotonic() - wait
            if left < 5:
                break
            await asyncio.sleep(wait)
            try:
                resp = await client.post(GEMINI_URL % model, json=_payload(parts, model), headers=headers,
                                         timeout=min(TIMEOUT_S, left))
            except httpx.TimeoutException:
                print("[%s] %s timed out, trying again" % (label, model))
                resp = None
                continue
            if resp.status_code not in RETRY_STATUSES:
                break
            print("[%s] %s returned %d, trying again" % (label, model, resp.status_code))
        if resp is None:
            raise ValueError("Gemini didn't answer in time. Try again, or use the demo data.")
        if resp.status_code == 404:
            # Usually a retired model name: list the ones this key can use.
            models = await client.get(GEMINI_LIST_URL, headers=headers, params={"pageSize": 200})
            names = [m["name"].split("/")[-1] for m in models.json().get("models", [])
                     if "generateContent" in m.get("supportedGenerationMethods", [])]
            raise ValueError("model %r not found (%s). Set GEMINI_MODEL to one of: %s"
                             % (model, resp.text[:300], ", ".join(names)))
    if resp.is_error:
        # Google's error body says why (bad key, quota, image too large...).
        raise ValueError("Gemini returned %d: %s" % (resp.status_code, resp.text[:500]))
    print("[%s] answered by %s" % (label, model))
    # Newer models may return "thought" parts before the answer; keep only the answer text.
    answer = resp.json()["candidates"][0]["content"]["parts"]
    return extract_json("".join(p.get("text", "") for p in answer if not p.get("thought")))
