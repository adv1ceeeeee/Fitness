-- Adds performed_at to sets (exact timestamp for ML time-of-day analysis)
-- and session_rpe to training_sessions (overall session difficulty 1-10).

-- sets.performed_at
alter table sets
  add column if not exists performed_at timestamptz not null default now();

-- Back-fill historical rows: use session date + midnight UTC as approximation
update sets s
set performed_at = (
  select (ts.date::text || 'T12:00:00Z')::timestamptz
  from training_sessions ts
  where ts.id = s.training_session_id
)
where performed_at = now(); -- only rows just defaulted

-- training_sessions.session_rpe
alter table training_sessions
  add column if not exists session_rpe smallint
    check (session_rpe between 1 and 10);
