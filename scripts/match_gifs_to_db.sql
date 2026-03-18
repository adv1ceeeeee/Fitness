-- Step 1: Add gif_url column to exercises (if not exists)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS gif_url TEXT;

-- Step 2: Create temp table with ExerciseDB data
-- (paste the CSV from exercisedb_mapping.csv into here,
--  or use \copy in psql / import via Supabase dashboard)
CREATE TEMP TABLE exercisedb_map (
    exercisedb_id TEXT,
    name          TEXT,
    body_part     TEXT,
    equipment     TEXT,
    gif_url       TEXT
);

-- \copy exercisedb_map FROM 'scripts/exercisedb_mapping.csv' CSV HEADER;

-- Step 3: Match by name similarity and update gif_url
-- Uses pg_trgm for fuzzy match — covers plural/case/punctuation differences
CREATE EXTENSION IF NOT EXISTS pg_trgm;

UPDATE exercises e
SET gif_url = m.gif_url
FROM exercisedb_map m
WHERE e.gif_url IS NULL
  AND similarity(lower(e.name), lower(m.name)) > 0.4
  AND (
    -- Prefer exact match first (handled by ORDER in subquery)
    m.gif_url = (
      SELECT gif_url
      FROM exercisedb_map
      WHERE similarity(lower(e.name), lower(name)) > 0.4
      ORDER BY similarity(lower(e.name), lower(name)) DESC
      LIMIT 1
    )
  );

-- Step 4: Check how many matched
SELECT
  COUNT(*) FILTER (WHERE gif_url IS NOT NULL) AS matched,
  COUNT(*) FILTER (WHERE gif_url IS NULL)     AS unmatched,
  COUNT(*)                                     AS total
FROM exercises
WHERE is_standard = true;

-- Step 5: Review unmatched — maybe fix names manually
SELECT id, name FROM exercises WHERE gif_url IS NULL AND is_standard = true ORDER BY name;
