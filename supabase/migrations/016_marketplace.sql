-- ============================================================
-- Migration 016: marketplace + trainer accounts prep
-- Enables selling programs and assigning programs to clients.
-- ============================================================

-- ── 1. Trainer profile extension ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.trainer_profiles (
  user_id         UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  bio             TEXT,
  specialization  TEXT[],   -- e.g. ['powerlifting', 'weight_loss']
  instagram_url   TEXT,
  telegram_handle TEXT,
  is_verified     BOOLEAN NOT NULL DEFAULT false,
  rating          NUMERIC(3,2),   -- 0.00–5.00, updated by trigger
  clients_count   INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.trainer_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view trainer profiles" ON public.trainer_profiles
  FOR SELECT USING (true);

CREATE POLICY "Trainers manage own profile" ON public.trainer_profiles
  FOR ALL USING (auth.uid() = user_id);

-- ── 2. Marketplace fields on workouts ────────────────────────────────────────
-- is_public:       visible in marketplace
-- price_kopecks:   0 = free, >0 = paid
-- trainer_id:      non-null = created by a trainer (for commission calculation)
-- cover_image_url: marketplace card image
-- description:     long-form program description shown on listing page
-- downloads_count: denormalised counter (incremented via trigger)

ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS is_public        BOOLEAN  NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS price_kopecks    INTEGER  NOT NULL DEFAULT 0
    CHECK (price_kopecks >= 0),
  ADD COLUMN IF NOT EXISTS trainer_id       UUID     REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cover_image_url  TEXT,
  ADD COLUMN IF NOT EXISTS description      TEXT,
  ADD COLUMN IF NOT EXISTS downloads_count  INTEGER  NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS workouts_marketplace_idx
  ON public.workouts (is_public, downloads_count DESC)
  WHERE is_public = true;

CREATE INDEX IF NOT EXISTS workouts_trainer_id_idx
  ON public.workouts (trainer_id)
  WHERE trainer_id IS NOT NULL;

-- ── 3. Program purchases ──────────────────────────────────────────────────────
-- One row per (buyer, program) pair. Unique ensures no double-purchase.

CREATE TABLE IF NOT EXISTS public.program_purchases (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id        UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  workout_id      UUID        NOT NULL REFERENCES public.workouts(id) ON DELETE CASCADE,
  amount_kopecks  INTEGER     NOT NULL DEFAULT 0,
  store           TEXT        NOT NULL DEFAULT 'internal',  -- 'rustore' | 'internal'
  created_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (buyer_id, workout_id)
);

CREATE INDEX IF NOT EXISTS program_purchases_buyer_idx
  ON public.program_purchases (buyer_id);
CREATE INDEX IF NOT EXISTS program_purchases_workout_idx
  ON public.program_purchases (workout_id);

ALTER TABLE public.program_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Buyers view own purchases" ON public.program_purchases
  FOR SELECT USING (auth.uid() = buyer_id);

-- Trainer can see who bought their program (for analytics)
CREATE POLICY "Trainers view purchases of own programs" ON public.program_purchases
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.trainer_id = auth.uid()
    )
  );

-- ── 4. Trainer ↔ Client assignments ──────────────────────────────────────────
-- Trainer assigns a program to a client (direct coaching flow).

CREATE TABLE IF NOT EXISTS public.trainer_clients (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  client_id   UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  workout_id  UUID        REFERENCES public.workouts(id) ON DELETE SET NULL,
  status      TEXT        NOT NULL DEFAULT 'active',  -- 'active' | 'paused' | 'ended'
  started_at  TIMESTAMPTZ DEFAULT NOW(),
  ended_at    TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (trainer_id, client_id)
);

CREATE INDEX IF NOT EXISTS trainer_clients_trainer_idx ON public.trainer_clients (trainer_id);
CREATE INDEX IF NOT EXISTS trainer_clients_client_idx  ON public.trainer_clients (client_id);

ALTER TABLE public.trainer_clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Trainers manage own clients" ON public.trainer_clients
  FOR ALL USING (auth.uid() = trainer_id);

CREATE POLICY "Clients view own trainer assignments" ON public.trainer_clients
  FOR SELECT USING (auth.uid() = client_id);

-- ── 5. Trigger: increment downloads_count on purchase ────────────────────────
CREATE OR REPLACE FUNCTION public.increment_workout_downloads()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.workouts
  SET downloads_count = downloads_count + 1
  WHERE id = NEW.workout_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER program_purchase_increment_downloads
  AFTER INSERT ON public.program_purchases
  FOR EACH ROW EXECUTE FUNCTION public.increment_workout_downloads();
