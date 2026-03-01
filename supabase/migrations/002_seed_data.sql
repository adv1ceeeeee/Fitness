-- SportWAI: Seed exercises and standard programs

-- Exercises
INSERT INTO exercises (id, name, category, description, is_standard) VALUES
  (gen_random_uuid(), 'Жим лежа', 'chest', 'Базовое упражнение на грудь', true),
  (gen_random_uuid(), 'Приседания со штангой', 'legs', 'Базовое упражнение на ноги', true),
  (gen_random_uuid(), 'Становая тяга', 'back', 'Базовое упражнение на спину', true),
  (gen_random_uuid(), 'Тяга верхнего блока', 'back', 'Упражнение на широчайшие', true),
  (gen_random_uuid(), 'Жим гантелей сидя', 'shoulders', 'Упражнение на плечи', true),
  (gen_random_uuid(), 'Подъем штанги на бицепс', 'arms', 'Упражнение на бицепс', true),
  (gen_random_uuid(), 'Французский жим', 'arms', 'Упражнение на трицепс', true),
  (gen_random_uuid(), 'Беговая дорожка', 'cardio', 'Кардио', true),
  (gen_random_uuid(), 'Велосипед', 'cardio', 'Кардио', true)
;

-- Standard programs will be created per-user or as templates
-- We create a "system" user or use null user_id for templates
-- For MVP: standard programs are created in the app when user first views them
-- Or we can add a template_workouts table. Simpler: create in app from predefined data.
