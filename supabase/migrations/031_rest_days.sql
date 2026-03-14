-- Add rest_days array to workouts (days explicitly marked as rest days)
alter table workouts
  add column if not exists rest_days int[] not null default '{}';
