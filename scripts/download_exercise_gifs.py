"""
Download exercise images from free-exercise-db (GitHub, public domain)
and upload to Supabase Storage.

Source: https://github.com/yuhonas/free-exercise-db
Images: JPG (2 per exercise — start + end position)
Count:  ~873 exercises

Usage:
    pip install requests
    SUPABASE_URL=https://xxx.supabase.co \
    SUPABASE_SERVICE_KEY=your_service_role_key \
    python scripts/download_exercise_gifs.py
"""

import os
import time
import requests
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
BUCKET       = "exercise-gifs"
IMG_DIR      = Path("scripts/exercise_images")

RAW_BASE  = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"
JSON_URL  = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

# ── Step 1: Fetch exercise list ───────────────────────────────────────────────

def fetch_exercises():
    print("Fetching exercise list from free-exercise-db...")
    r = requests.get(JSON_URL, timeout=30)
    r.raise_for_status()
    data = r.json()
    print(f"  Total: {len(data)} exercises")
    return data

# ── Step 2: Download images ───────────────────────────────────────────────────

def download_images(exercises):
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    skipped = 0
    downloaded = 0
    failed = 0

    for ex in exercises:
        ex_id  = ex["id"]
        images = ex.get("images", [])
        if not images:
            continue

        # Take only the first image (starting position)
        img_path = images[0]  # e.g. "3_4_Sit-Up/0.jpg"
        dest = IMG_DIR / f"{ex_id}.jpg"

        if dest.exists():
            skipped += 1
            continue

        url = f"{RAW_BASE}/{img_path}"
        try:
            r = requests.get(url, timeout=15)
            r.raise_for_status()
            dest.write_bytes(r.content)
            downloaded += 1
            print(f"  [{downloaded}] {ex['name']}", end="\r")
        except Exception as e:
            print(f"\n  WARN {ex_id}: {e}")
            failed += 1
        time.sleep(0.05)

    print(f"\nDownloaded: {downloaded} | Skipped: {skipped} | Failed: {failed}")

# ── Step 3: Upload to Supabase Storage ────────────────────────────────────────

def upload_to_supabase(exercises):
    storage_url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}"
    id_to_name  = {ex["id"]: ex["name"] for ex in exercises}

    img_files = list(IMG_DIR.glob("*.jpg"))
    print(f"Uploading {len(img_files)} images to Supabase Storage (bucket: {BUCKET})...")

    ok = 0
    fail = 0

    for img_path in img_files:
        ex_id = img_path.stem
        object_url = f"{storage_url}/{ex_id}.jpg"
        try:
            with open(img_path, "rb") as f:
                r = requests.post(
                    object_url,
                    headers={
                        "Authorization": f"Bearer {SUPABASE_KEY}",
                        "Content-Type":  "image/jpeg",
                    },
                    data=f,
                    timeout=30,
                )
            if r.status_code in (200, 201):
                ok += 1
                print(f"  [{ok}] {id_to_name.get(ex_id, ex_id)}", end="\r")
            elif "already exists" in r.text:
                ok += 1
            else:
                print(f"\n  WARN {ex_id}: {r.status_code} {r.text[:80]}")
                fail += 1
        except Exception as e:
            print(f"\n  ERROR {ex_id}: {e}")
            fail += 1

    print(f"\nUpload done: {ok} ok, {fail} failed")

# ── Step 4: Save CSV mapping ──────────────────────────────────────────────────

def save_mapping(exercises):
    public_base = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}"
    out = Path("scripts/exercisedb_mapping.csv")

    lines = ["exercisedb_id,name,category,primary_muscle,image_url"]
    for ex in exercises:
        ex_id   = ex["id"]
        name    = ex["name"].replace(",", " ")
        cat     = ex.get("category", "")
        muscle  = (ex.get("primaryMuscles") or [""])[0]
        img_url = f"{public_base}/{ex_id}.jpg"
        lines.append(f"{ex_id},{name},{cat},{muscle},{img_url}")

    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"Mapping saved to {out}  ({len(exercises)} rows)")

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    exercises = fetch_exercises()
    download_images(exercises)
    upload_to_supabase(exercises)
    save_mapping(exercises)
    print("\nDone! Next: run scripts/match_gifs_to_db.sql in Supabase SQL editor.")
