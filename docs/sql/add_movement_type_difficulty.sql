-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: add movement_type and difficulty to exercises
-- Run in Supabase → SQL Editor
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE exercises
  ADD COLUMN IF NOT EXISTS movement_type VARCHAR,
  ADD COLUMN IF NOT EXISTS difficulty    VARCHAR;

-- ── Chest (Грудь) ─────────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'press'
WHERE category = 'chest' AND (
  name ILIKE '%press%' OR name ILIKE '%жим%' OR name ILIKE '%push-up%'
  OR name ILIKE '%отжим%' OR name ILIKE '%dip%' OR name ILIKE '%брус%'
);
UPDATE exercises SET movement_type = 'fly'
WHERE category = 'chest' AND (
  name ILIKE '%fly%' OR name ILIKE '%flye%' OR name ILIKE '%разводк%'
  OR name ILIKE '%crossover%' OR name ILIKE '%кроссов%' OR name ILIKE '%pec deck%'
  OR name ILIKE '%бабочк%'
);

-- ── Back (Спина) ───────────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'row'
WHERE category = 'back' AND (
  name ILIKE '%row%' OR name ILIKE '%тяга%' OR name ILIKE '%deadlift%'
  OR name ILIKE '%становая%' OR name ILIKE '%t-bar%' OR name ILIKE '%pullover%'
);
UPDATE exercises SET movement_type = 'raise'
WHERE category = 'back' AND (
  name ILIKE '%pull-up%' OR name ILIKE '%pullup%' OR name ILIKE '%chin%'
  OR name ILIKE '%подтягив%' OR name ILIKE '%pulldown%' OR name ILIKE '%lat%'
  OR name ILIKE '%тяга верт%' OR name ILIKE '%блок верх%'
);
UPDATE exercises SET movement_type = 'extension'
WHERE category = 'back' AND (
  name ILIKE '%hyperextension%' OR name ILIKE '%back extension%'
  OR name ILIKE '%гиперэкстен%' OR name ILIKE '%good morning%'
);

-- ── Shoulders (Плечи) ─────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'press'
WHERE category = 'shoulders' AND (
  name ILIKE '%press%' OR name ILIKE '%жим%' OR name ILIKE '%overhead%'
  OR name ILIKE '%military%' OR name ILIKE '%arnold%'
);
UPDATE exercises SET movement_type = 'raise'
WHERE category = 'shoulders' AND (
  name ILIKE '%lateral raise%' OR name ILIKE '%front raise%'
  OR name ILIKE '%подъём%' OR name ILIKE '%подъем%' OR name ILIKE '%махи%'
  OR name ILIKE '%raise%'
);
UPDATE exercises SET movement_type = 'row'
WHERE category = 'shoulders' AND (
  name ILIKE '%upright row%' OR name ILIKE '%shrug%' OR name ILIKE '%шраг%'
  OR name ILIKE '%тяга к подбородку%'
);
UPDATE exercises SET movement_type = 'fly'
WHERE category = 'shoulders' AND (
  name ILIKE '%rear delt%' OR name ILIKE '%face pull%' OR name ILIKE '%reverse fly%'
  OR name ILIKE '%задний пучок%' OR name ILIKE '%обратн%'
);

-- ── Arms (Руки) ───────────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'curl'
WHERE category = 'arms' AND (
  name ILIKE '%curl%' OR name ILIKE '%сгибан%' OR name ILIKE '%bicep%'
  OR name ILIKE '%бицепс%' OR name ILIKE '%hammer%' OR name ILIKE '%молот%'
  OR name ILIKE '%preacher%' OR name ILIKE '%scott%' OR name ILIKE '%скотт%'
);
UPDATE exercises SET movement_type = 'extension'
WHERE category = 'arms' AND (
  name ILIKE '%extension%' OR name ILIKE '%разгибан%' OR name ILIKE '%tricep%'
  OR name ILIKE '%трицепс%' OR name ILIKE '%skull crusher%' OR name ILIKE '%pushdown%'
  OR name ILIKE '%french%' OR name ILIKE '%close grip%' OR name ILIKE '%узким хват%'
);

-- ── Legs (Ноги) ───────────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'squat'
WHERE category = 'legs' AND (
  name ILIKE '%squat%' OR name ILIKE '%присед%' OR name ILIKE '%goblet%'
  OR name ILIKE '%front squat%' OR name ILIKE '%box squat%'
);
UPDATE exercises SET movement_type = 'lunge'
WHERE category = 'legs' AND (
  name ILIKE '%lunge%' OR name ILIKE '%выпад%' OR name ILIKE '%bulgarian%'
  OR name ILIKE '%split squat%' OR name ILIKE '%step-up%' OR name ILIKE '%степ%'
);
UPDATE exercises SET movement_type = 'press'
WHERE category = 'legs' AND (
  name ILIKE '%leg press%' OR name ILIKE '%жим ног%' OR name ILIKE '%hack squat%'
);
UPDATE exercises SET movement_type = 'curl'
WHERE category = 'legs' AND (
  name ILIKE '%leg curl%' OR name ILIKE '%hamstring%' OR name ILIKE '%nordic%'
  OR name ILIKE '%сгибан%' OR name ILIKE '%бедр%'
  OR name ILIKE '%romanian%' OR name ILIKE '%румынс%'
);
UPDATE exercises SET movement_type = 'extension'
WHERE category = 'legs' AND (
  name ILIKE '%leg extension%' OR name ILIKE '%разгибан%'
);
UPDATE exercises SET movement_type = 'raise'
WHERE category = 'legs' AND (
  name ILIKE '%calf raise%' OR name ILIKE '%подъём на носки%'
  OR name ILIKE '%икр%' OR name ILIKE '%donkey%'
);

-- ── Core (Пресс) ──────────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'curl'
WHERE category = 'core' AND (
  name ILIKE '%crunch%' OR name ILIKE '%скручивани%' OR name ILIKE '%sit-up%'
  OR name ILIKE '%sit up%' OR name ILIKE '%bicycle%' OR name ILIKE '%велосипед%'
  OR name ILIKE '%cable crunch%'
);
UPDATE exercises SET movement_type = 'plank'
WHERE category = 'core' AND (
  name ILIKE '%plank%' OR name ILIKE '%планка%' OR name ILIKE '%ab wheel%'
  OR name ILIKE '%ролик%' OR name ILIKE '%hollow%' OR name ILIKE '%dead bug%'
);
UPDATE exercises SET movement_type = 'raise'
WHERE category = 'core' AND (
  name ILIKE '%leg raise%' OR name ILIKE '%knee raise%' OR name ILIKE '%подъём ног%'
  OR name ILIKE '%подъем ног%' OR name ILIKE '%hanging%' OR name ILIKE '%висе%'
);

-- ── Cardio ────────────────────────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'cardio' WHERE category = 'cardio';

-- ── Fallback: everything else ─────────────────────────────────────────────────
UPDATE exercises SET movement_type = 'other'
WHERE movement_type IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- Difficulty (only for standard exercises — custom exercises left NULL)
-- ─────────────────────────────────────────────────────────────────────────────

-- Beginner: machines, bodyweight basics, cables with simple patterns
UPDATE exercises SET difficulty = 'beginner'
WHERE is_standard = true AND (
  name ILIKE '%machine%' OR name ILIKE '%тренажёр%' OR name ILIKE '%тренажер%'
  OR name ILIKE '%cable%' OR name ILIKE '%блок%'
  OR name ILIKE '%push-up%' OR name ILIKE '%отжимания%'
  OR name ILIKE '%plank%' OR name ILIKE '%планка%'
  OR name ILIKE '%leg press%' OR name ILIKE '%жим ног%'
  OR name ILIKE '%leg extension%' OR name ILIKE '%leg curl%'
  OR name ILIKE '%lat pulldown%' OR name ILIKE '%блок%верт%'
  OR name ILIKE '%seated row%' OR name ILIKE '%dumbbell%' AND name ILIKE '%lateral%'
);

-- Advanced: compound lifts and technically demanding movements
UPDATE exercises SET difficulty = 'advanced'
WHERE is_standard = true AND (
  name ILIKE '%deadlift%' OR name ILIKE '%становая%'
  OR name ILIKE '%snatch%' OR name ILIKE '%рывок%'
  OR name ILIKE '%clean%' OR name ILIKE '%толчок%'
  OR name ILIKE '%muscle-up%' OR name ILIKE '%мышечный выход%'
  OR name ILIKE '%front squat%' OR name ILIKE '%фронтальн%'
  OR name ILIKE '%overhead squat%'
  OR name ILIKE '%nordic%'
);

-- Intermediate: everything else that's standard
UPDATE exercises SET difficulty = 'intermediate'
WHERE is_standard = true AND difficulty IS NULL;
