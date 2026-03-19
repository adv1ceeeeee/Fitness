-- Migration 043: user feedback table
-- Stores all in-app feedback: NPS scores, micro-surveys, screen thumbs, free-form messages.

CREATE TABLE IF NOT EXISTS feedback (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category     TEXT        NOT NULL,  -- 'nps' | 'micro_survey' | 'screen' | 'bug' | 'feature' | 'general'
  rating       SMALLINT,              -- NPS: 0–10; thumbs: 1 (up) / -1 (down)
  message      TEXT,                  -- free-form text (optional)
  metadata     JSONB       NOT NULL DEFAULT '{}',  -- {screen, feature_request, etc.}
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS feedback_user_id_idx ON feedback (user_id);
CREATE INDEX IF NOT EXISTS feedback_category_idx ON feedback (category);
CREATE INDEX IF NOT EXISTS feedback_created_at_idx ON feedback (created_at DESC);

-- RLS
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own feedback"
  ON feedback FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read own feedback"
  ON feedback FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
