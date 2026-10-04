"""The one place that talks to the Gemini API. Gemini only reads and writes text;
every number the app shows is computed afterwards in Python.

Needs GEMINI_API_KEY in the server's environment (never in a file).
"""
import asyncio
import json
import os
from typing import Any, Dict, List

import httpx

# Check Google AI Studio for the current model name and override with GEMINI_MODEL if needed.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
# Tried in order when the main model is overloaded (503) or rate limited (429).
GEMINI_FALLBACK_MODELS = os.getenv(
    "GEMINI_FALLBACK_MODELS", "gemini-3.5-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite").split(",")
RETRY_STATUSES = {429, 500, 503}
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
GEMINI_LIST_URL = "https://generativelanguage.googleapis.com/v1beta/models"


def has_api_key() -> bool:
    return bool(os.getenv("GEMINI_API_KEY"))


def extract_json(text: str) -> Any:
    """Parse Gemini's answer, tolerating a ```json fence around it."""
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    return json.loads(text)


async def generate_json(parts: List[Dict[str, Any]], label: str) -> Any:
    """Send `parts` (text and/or inlineData) and return the parsed JSON answer.

    Raises ValueError with Google's explanation if every model fails.
    `label` only tags the server log lines (e.g. "receipt").
    """
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise ValueError("GEMINI_API_KEY is not set on the server")
    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0},
    }
    headers = {"x-goog-api-key": key}
    async with httpx.AsyncClient(timeout=60) as client:
        # Main model, one retry after a short wait, then each fallback model.
        attempts = [(GEMINI_MODEL, 0), (GEMINI_MODEL, 2)] + [(m.strip(), 0) for m in GEMINI_FALLBACK_MODELS]
        for model, wait in attempts:
            await asyncio.sleep(wait)
            resp = await client.post(GEMINI_URL % model, json=payload, headers=headers)
            if resp.status_code not in RETRY_STATUSES:
                break
            print("[%s] %s returned %d, trying again" % (label, model, resp.status_code))
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
