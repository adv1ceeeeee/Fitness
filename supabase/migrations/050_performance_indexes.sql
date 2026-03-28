-- Partial index: speeds up volume/calorie aggregation queries that filter
-- out warm-up sets (the most frequent sets query pattern in analytics).
CREATE INDEX IF NOT EXISTS idx_sets_session_no_warmup
    ON sets (training_session_id)
    WHERE is_warmup = false;

-- Partial index: speeds up completed-sets lookup used throughout analytics.
CREATE INDEX IF NOT EXISTS idx_sets_session_completed
    ON sets (training_session_id, workout_exercise_id)
    WHERE completed = true;

-- Index for performed_at range scans (getRecentlyTrainedCategories).
CREATE INDEX IF NOT EXISTS idx_sets_performed_at
    ON sets (performed_at)
    WHERE completed = true AND workout_exercise_id IS NOT NULL;
