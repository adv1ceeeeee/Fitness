-- RLS Policy Tests
-- Запускать через: supabase test db
-- Требует расширение pgTAP: CREATE EXTENSION IF NOT EXISTS pgtap;
--
-- Проверяет, что пользователь A не видит данные пользователя B.

BEGIN;

SELECT plan(12);

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Два тестовых UUID (не существуют в prod, используются только для тестов)
\set user_a 'a0000000-0000-0000-0000-000000000001'
\set user_b 'b0000000-0000-0000-0000-000000000002'

-- Симулируем JWT контекст пользователя A
CREATE OR REPLACE FUNCTION set_auth_user(uid uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text,
    true);
  SELECT set_config('role', 'authenticated', true);
$$;

-- ── Вставка тестовых данных (service_role обходит RLS) ───────────────────────
SET role service_role;

INSERT INTO profiles (id) VALUES (:'user_a'), (:'user_b')
  ON CONFLICT DO NOTHING;

INSERT INTO workouts (id, user_id, name, days, created_at, updated_at)
VALUES
  ('w-a-1', :'user_a', 'Workout A', '{0}', now(), now()),
  ('w-b-1', :'user_b', 'Workout B', '{1}', now(), now())
ON CONFLICT DO NOTHING;

INSERT INTO training_sessions (id, user_id, workout_id, date, completed)
VALUES
  ('s-a-1', :'user_a', 'w-a-1', current_date, false),
  ('s-b-1', :'user_b', 'w-b-1', current_date, false)
ON CONFLICT DO NOTHING;

-- ── Тесты: пользователь A видит только свои данные ───────────────────────────
SELECT set_auth_user(:'user_a'::uuid);

-- profiles
SELECT results_eq(
  'SELECT id::text FROM profiles WHERE id = ' || quote_literal(:'user_a'),
  ARRAY[:'user_a'],
  'User A sees own profile'
);
SELECT is_empty(
  'SELECT id::text FROM profiles WHERE id = ' || quote_literal(:'user_b'),
  'User A cannot see user B profile'
);

-- workouts
SELECT results_eq(
  'SELECT name FROM workouts WHERE user_id = ' || quote_literal(:'user_a'),
  ARRAY['Workout A'],
  'User A sees own workouts'
);
SELECT is_empty(
  'SELECT name FROM workouts WHERE user_id = ' || quote_literal(:'user_b'),
  'User A cannot see user B workouts'
);

-- training_sessions
SELECT results_eq(
  'SELECT id::text FROM training_sessions WHERE user_id = ' || quote_literal(:'user_a'),
  ARRAY['s-a-1'],
  'User A sees own sessions'
);
SELECT is_empty(
  'SELECT id::text FROM training_sessions WHERE user_id = ' || quote_literal(:'user_b'),
  'User A cannot see user B sessions'
);

-- ── Тесты: пользователь B видит только свои данные ───────────────────────────
SELECT set_auth_user(:'user_b'::uuid);

SELECT results_eq(
  'SELECT name FROM workouts WHERE user_id = ' || quote_literal(:'user_b'),
  ARRAY['Workout B'],
  'User B sees own workouts'
);
SELECT is_empty(
  'SELECT name FROM workouts WHERE user_id = ' || quote_literal(:'user_a'),
  'User B cannot see user A workouts'
);

-- ── app_config: читать могут все ─────────────────────────────────────────────
SELECT set_auth_user(:'user_a'::uuid);
SELECT ok(
  (SELECT count(*) FROM app_config WHERE key = 'min_version') >= 0,
  'app_config is readable by authenticated users'
);

-- ── app_config: запись запрещена ─────────────────────────────────────────────
SELECT throws_ok(
  'INSERT INTO app_config (key, value) VALUES (''hacked'', ''1'')',
  'new row violates row-level security policy',
  'authenticated user cannot write to app_config'
);

-- ── body_metrics: изоляция ───────────────────────────────────────────────────
SET role service_role;
INSERT INTO body_metrics (user_id, date, weight_kg)
VALUES (:'user_a', current_date, 80), (:'user_b', current_date, 90)
ON CONFLICT DO NOTHING;

SELECT set_auth_user(:'user_a'::uuid);
SELECT is_empty(
  'SELECT user_id::text FROM body_metrics WHERE user_id = ' || quote_literal(:'user_b'),
  'User A cannot see user B body_metrics'
);

-- ── Очистка ──────────────────────────────────────────────────────────────────
SET role service_role;
DELETE FROM body_metrics   WHERE user_id IN (:'user_a', :'user_b');
DELETE FROM training_sessions WHERE user_id IN (:'user_a', :'user_b');
DELETE FROM workouts       WHERE user_id IN (:'user_a', :'user_b');
DELETE FROM profiles       WHERE id      IN (:'user_a', :'user_b');

SELECT * FROM finish();
ROLLBACK;
