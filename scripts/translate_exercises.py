"""
Translate exercise names from English to Russian using Google Translate (free, no API key needed).
Updates name_ru column in Supabase exercises table.

Usage:
    pip install requests deep-translator
    SUPABASE_URL=https://xxx.supabase.co \
    SUPABASE_SERVICE_KEY=your_service_role_key \
    python scripts/translate_exercises.py
"""

import os
import time
import requests
from deep_translator import GoogleTranslator

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}

translator = GoogleTranslator(source="en", target="ru")

def fetch_untranslated():
    url = f"{SUPABASE_URL}/rest/v1/exercises?name_ru=is.null&is_standard=eq.true&select=id,name&limit=1000"
    r = requests.get(url, headers=HEADERS, timeout=30)
    r.raise_for_status()
    return r.json()

def update_name_ru(exercise_id: str, name_ru: str):
    url = f"{SUPABASE_URL}/rest/v1/exercises?id=eq.{exercise_id}"
    r = requests.patch(url, headers=HEADERS, json={"name_ru": name_ru}, timeout=15)
    return r.status_code in (200, 204)

if __name__ == "__main__":
    exercises = fetch_untranslated()
    print(f"Translating {len(exercises)} exercises...")

    ok = 0
    fail = 0

    for i, ex in enumerate(exercises):
        try:
            translated = translator.translate(ex["name"])
            if update_name_ru(ex["id"], translated):
                ok += 1
                print(f"  [{ok}] {ex['name']} -> {translated}", end="\r")
            else:
                fail += 1
        except Exception as e:
            print(f"\n  WARN [{ex['name']}]: {e}")
            fail += 1

        # Polite rate limiting
        time.sleep(0.1)

    print(f"\nDone: {ok} translated, {fail} failed.")
