"""
Import exercises from free-exercise-db into Supabase exercises table.

- Deletes existing is_standard exercises
- Inserts 873 exercises with gif_url and description set
- Maps primaryMuscles → our category schema

Usage:
    pip install requests
    SUPABASE_URL=https://xxx.supabase.co \
    SUPABASE_SERVICE_KEY=your_service_role_key \
    python scripts/import_exercises.py
"""

import os
import json
import requests

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
PUBLIC_BASE   = f"{SUPABASE_URL}/storage/v1/object/public/exercise-gifs"
JSON_URL      = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}

# ── Map primary muscle → our category ─────────────────────────────────────────

MUSCLE_TO_CATEGORY = {
    "chest": "chest",
    "middle back": "back",
    "lower back": "back",
    "lats": "back",
    "traps": "back",
    "shoulders": "shoulders",
    "biceps": "arms",
    "triceps": "arms",
    "forearms": "arms",
    "quadriceps": "legs",
    "hamstrings": "legs",
    "glutes": "legs",
    "calves": "legs",
    "adductors": "legs",
    "abductors": "legs",
    "abdominals": "core",
    "cardiovascular system": "cardio",
    "neck": "back",
}

def muscle_to_category(muscles: list) -> str:
    for m in muscles:
        cat = MUSCLE_TO_CATEGORY.get(m.lower())
        if cat:
            return cat
    return "core"  # fallback

# ── Step 1: fetch exercises ────────────────────────────────────────────────────

def fetch_exercises():
    print("Fetching exercises from free-exercise-db...")
    r = requests.get(JSON_URL, timeout=30)
    r.raise_for_status()
    data = r.json()
    print(f"  Total: {len(data)} exercises")
    return data

# ── Step 2: delete existing standard exercises ────────────────────────────────

def delete_standard_exercises():
    print("Deleting existing is_standard exercises...")
    # Delete workout_exercises that reference standard exercises first
    url = f"{SUPABASE_URL}/rest/v1/workout_exercises"
    # We need to delete via a join — use RPC or just delete exercises (cascade)
    # Assuming ON DELETE CASCADE or we handle it manually
    # First delete standard exercises directly
    url = f"{SUPABASE_URL}/rest/v1/exercises?is_standard=eq.true"
    r = requests.delete(url, headers=HEADERS, timeout=30)
    if r.status_code in (200, 204):
        print("  Done.")
    else:
        print(f"  WARN: {r.status_code} {r.text[:200]}")

# ── Step 3: insert new exercises ──────────────────────────────────────────────

def insert_exercises(exercises: list):
    print("Inserting exercises...")
    url = f"{SUPABASE_URL}/rest/v1/exercises"
    ok = 0
    fail = 0
    batch = []

    for ex in exercises:
        ex_id   = ex["id"]
        name    = ex["name"]
        muscles = ex.get("primaryMuscles", [])
        cat     = muscle_to_category(muscles)
        images  = ex.get("images", [])
        gif_url = f"{PUBLIC_BASE}/{ex_id}.jpg" if images else None
        instructions = ex.get("instructions", [])
        description  = " ".join(instructions) if instructions else None

        batch.append({
            "name":        name,
            "category":    cat,
            "description": description,
            "gif_url":     gif_url,
            "is_standard": True,
        })

        if len(batch) >= 50:
            ok += _send_batch(url, batch)
            batch = []

    if batch:
        ok += _send_batch(url, batch)

    print(f"Inserted: {ok} | Failed: {fail}")

def _send_batch(url, batch):
    r = requests.post(url, headers=HEADERS, json=batch, timeout=30)
    if r.status_code in (200, 201):
        print(f"  +{len(batch)}", end="\r")
        return len(batch)
    else:
        print(f"\n  WARN: {r.status_code} {r.text[:200]}")
        return 0

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    exercises = fetch_exercises()
    delete_standard_exercises()
    insert_exercises(exercises)
    print("\nDone! Next: run scripts/translate_exercises.py to add Russian names.")
