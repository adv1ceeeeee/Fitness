-- Add per-day start times to workout programs.
-- day_times is a JSONB map: {"0": "07:30", "2": "09:00"} where key = day index (0=Mon...6=Sun).
alter table workouts add column if not exists day_times jsonb not null default '{}';
