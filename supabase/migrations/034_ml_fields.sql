-- ML signal fields for progressive overload, recovery and dropout models.

-- sets.reps_target — planned reps; compare with reps to detect failure
alter table sets
  add column if not exists reps_target int;

-- wellness_logs: subjective sleep quality + muscle soreness
alter table wellness_logs
  add column if not exists sleep_quality smallint check (sleep_quality between 1 and 5);

alter table wellness_logs
  add column if not exists soreness smallint check (soreness between 1 and 5);

-- training_sessions.streak_at_start — consecutive workout days at session creation
alter table training_sessions
  add column if not exists streak_at_start int;
