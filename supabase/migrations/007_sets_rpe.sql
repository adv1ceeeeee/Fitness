-- SportWAI: добавить поле RPE (Rate of Perceived Exertion, 0–10) в таблицу сетов

ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS rpe INTEGER CHECK (rpe >= 0 AND rpe <= 10);
