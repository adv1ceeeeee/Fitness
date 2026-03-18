"""
Download exercise GIFs from ExerciseDB and upload to Supabase Storage.

Usage:
    pip install requests supabase
    python scripts/download_exercise_gifs.py

Set env vars before running:
    RAPIDAPI_KEY=your_key_here
    SUPABASE_URL=https://xxxx.supabase.co
    SUPABASE_SERVICE_KEY=your_service_role_key  (not anon key!)
"""

import os
import time
import requests
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

RAPIDAPI_KEY   = os.environ["RAPIDAPI_KEY"]
SUPABASE_URL   = os.environ["SUPABASE_URL"]
SUPABASE_KEY   = os.environ["SUPABASE_SERVICE_KEY"]  # service_role, not anon
BUCKET         = "exercise-gifs"
GIF_DIR        = Path("scripts/gifs")

HEADERS = {
    "X-RapidAPI-Key":  RAPIDAPI_KEY,
    "X-RapidAPI-Host": "exercisedb.p.rapidapi.com",
}

# ── Step 1: Fetch all exercise metadata ───────────────────────────────────────

def fetch_all_exercises():
    print("Fetching exercise list from ExerciseDB...")
    resp = requests.get(
        "https://exercisedb.p.rapidapi.com/exercises",
        headers=HEADERS,
        params={"limit": 1500, "offset": 0},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    print(f"  Got {len(data)} exercises")
    return data

# ── Step 2: Download GIFs locally ─────────────────────────────────────────────

def download_gifs(exercises):
    GIF_DIR.mkdir(parents=True, exist_ok=True)
    skipped = 0
    for ex in exercises:
        ex_id  = ex["id"]
        gif_url = ex.get("gifUrl", "")
        if not gif_url:
            continue
        dest = GIF_DIR / f"{ex_id}.gif"
        if dest.exists():
            skipped += 1
            continue
        try:
            r = requests.get(gif_url, timeout=15)
            r.raise_for_status()
            dest.write_bytes(r.content)
        except Exception as e:
            print(f"  WARN: failed to download {ex_id}: {e}")
        time.sleep(0.05)  # be polite

    total = len(list(GIF_DIR.glob("*.gif")))
    print(f"Downloaded: {total} GIFs ({skipped} already cached)")

# ── Step 3: Upload to Supabase Storage ────────────────────────────────────────

def upload_to_supabase(exercises):
    storage_url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}"
    auth_headers = {
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type":  "image/gif",
    }

    # Map exercise id → name for logging
    id_to_name = {ex["id"]: ex["name"] for ex in exercises}

    gif_files = list(GIF_DIR.glob("*.gif"))
    print(f"Uploading {len(gif_files)} GIFs to Supabase Storage (bucket: {BUCKET})...")

    ok = 0
    fail = 0
    for gif_path in gif_files:
        ex_id = gif_path.stem
        object_path = f"{storage_url}/{ex_id}.gif"
        try:
            with open(gif_path, "rb") as f:
                r = requests.post(
                    object_path,
                    headers=auth_headers,
                    data=f,
                    timeout=30,
                )
            if r.status_code in (200, 201):
                ok += 1
            elif r.status_code == 400 and "already exists" in r.text:
                ok += 1  # already uploaded
            else:
                print(f"  WARN {ex_id} ({id_to_name.get(ex_id, '?')}): {r.status_code} {r.text[:80]}")
                fail += 1
        except Exception as e:
            print(f"  ERROR {ex_id}: {e}")
            fail += 1

    print(f"Upload done: {ok} ok, {fail} failed")

# ── Step 4: Print CSV mapping (exercisedb_id, name, gifUrl) ──────────────────

def print_mapping_csv(exercises):
    out = Path("scripts/exercisedb_mapping.csv")
    public_base = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}"
    lines = ["exercisedb_id,name,body_part,equipment,gif_url"]
    for ex in exercises:
        ex_id    = ex["id"]
        name     = ex["name"].replace(",", " ")
        body     = ex.get("bodyPart", "")
        equip    = ex.get("equipment", "")
        gif_url  = f"{public_base}/{ex_id}.gif"
        lines.append(f"{ex_id},{name},{body},{equip},{gif_url}")
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"Mapping saved to {out}  ({len(exercises)} rows)")

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    exercises = fetch_all_exercises()
    download_gifs(exercises)
    upload_to_supabase(exercises)
    print_mapping_csv(exercises)
    print("\nDone! Next step: run scripts/match_gifs_to_db.sql to update exercises table.")
