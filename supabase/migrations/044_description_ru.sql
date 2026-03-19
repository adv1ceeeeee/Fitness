-- Migration 044: Russian descriptions for exercises
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS description_ru TEXT;
