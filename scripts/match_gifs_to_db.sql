-- ─── Match exercise images from free-exercise-db to our exercises table ───────
--
-- 1. Apply migration 040 first (adds gif_url column + storage bucket)
-- 2. In Supabase Table Editor: create table exercisedb_map, import the CSV
--    OR use SQL below to create + populate manually
-- 3. Run the UPDATE below
-- 4. Check results

-- Step 1: Enable fuzzy matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Step 2: Create staging table
DROP TABLE IF EXISTS exercisedb_map;
CREATE TEMP TABLE exercisedb_map (
    exercisedb_id  TEXT,
    name           TEXT,
    category       TEXT,
    primary_muscle TEXT,
    image_url      TEXT
);

-- Step 3: Load CSV
-- Option A — psql CLI:
--   \copy exercisedb_map FROM 'scripts/exercisedb_mapping.csv' CSV HEADER;
--
-- Option B — Supabase dashboard:
--   Table Editor → New table → import CSV → then reference it here

-- Step 4: Update gif_url using fuzzy name match
UPDATE exercises e
SET gif_url = (
    SELECT m.image_url
    FROM exercisedb_map m
    ORDER BY similarity(lower(e.name), lower(m.name)) DESC
    LIMIT 1
)
WHERE e.gif_url IS NULL
  AND EXISTS (
    SELECT 1 FROM exercisedb_map m
    WHERE similarity(lower(e.name), lower(m.name)) > 0.35
  );

-- Step 5: Check results
SELECT
  COUNT(*) FILTER (WHERE gif_url IS NOT NULL) AS matched,
  COUNT(*) FILTER (WHERE gif_url IS NULL)     AS unmatched,
  COUNT(*)                                    AS total
FROM exercises
WHERE is_standard = true;

-- Step 6: See what didn't match
SELECT name FROM exercises
WHERE gif_url IS NULL AND is_standard = true
ORDER BY name;
