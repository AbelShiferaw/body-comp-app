-- Photo sessions and body measurements (HLD "Body proportions" and "Photo
-- estimate and DEXA calibration").
--
-- Guided front and side photos are the source of truth for proportions. Each
-- session's measurements are stored with source = 'photo'; a tape-measure edit
-- is a 'tape' row. The newest value per measurement wins, so an edit overrides
-- the photo value until the next photo session (current_body_measurements).
-- Raw photos are kept only with a model_training consent (storage_paths).
-- body_estimates and calibrations wait for the photo-estimate LLD.

create table public.photo_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  captured_at timestamptz not null default now(),
  capture_kind text not null default 'photos' check (capture_kind in ('photos', 'video')),
  sdk text check (char_length(sdk) <= 40),          -- e.g. 'prism', '3dlook', 'on_device'
  sdk_version text check (char_length(sdk_version) <= 40),
  -- Set when the session was taken around a DEXA scan, for calibration.
  paired_scan_id uuid,
  -- Paths in the private training-photos bucket; empty unless opted in.
  storage_paths text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (paired_scan_id, user_id)
    references public.scans (id, user_id) on delete set null (paired_scan_id)
);

create index photo_sessions_user_captured_idx on public.photo_sessions (user_id, captured_at desc);
create index photo_sessions_paired_scan_idx on public.photo_sessions (paired_scan_id, user_id);

alter table public.photo_sessions enable row level security;

-- Raw photos only with an active model_training consent.
create function public.photo_storage_allowed(p_paths text[])
returns boolean
language sql
stable
set search_path = ''
as $$
  select cardinality(p_paths) = 0 or exists (
    select 1 from public.consents c
    where c.user_id = (select auth.uid())
      and c.kind = 'model_training'
      and c.revoked_at is null
  );
$$;

create policy "photo_sessions: owner can read"
  on public.photo_sessions for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "photo_sessions: owner can create"
  on public.photo_sessions for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id and public.photo_storage_allowed(storage_paths)
  );

create policy "photo_sessions: owner can update"
  on public.photo_sessions for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id and public.photo_storage_allowed(storage_paths)
  );

create policy "photo_sessions: owner can delete"
  on public.photo_sessions for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create table public.body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Keys shared with the body_mapping package's BodyMeasurements.
  measurement text not null check (measurement in (
    'height', 'shoulders', 'chest', 'waist', 'hips',
    'upper_arm', 'thigh', 'calf', 'arm_length', 'leg_length'
  )),
  value_cm numeric(5, 1) not null check (value_cm > 0 and value_cm < 300),
  source text not null check (source in ('photo', 'tape')),
  photo_session_id uuid,
  measured_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- Photo values belong to a session; tape edits stand alone.
  check ((source = 'photo') = (photo_session_id is not null)),
  unique (photo_session_id, user_id, measurement),
  foreign key (photo_session_id, user_id)
    references public.photo_sessions (id, user_id) on delete cascade
);

create index body_measurements_current_idx
  on public.body_measurements (user_id, measurement, measured_at desc, created_at desc);
create index body_measurements_session_idx on public.body_measurements (photo_session_id, user_id);

alter table public.body_measurements enable row level security;

create policy "body_measurements: owner can read"
  on public.body_measurements for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "body_measurements: owner can add"
  on public.body_measurements for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "body_measurements: owner can correct"
  on public.body_measurements for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "body_measurements: owner can delete"
  on public.body_measurements for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- The value per measurement the body uses now: the newest one, whether from a
-- photo session or a tape edit. security_invoker keeps the caller's RLS.
create view public.current_body_measurements
with (security_invoker = true)
as
select distinct on (user_id, measurement)
  user_id, measurement, value_cm, source, photo_session_id, measured_at
from public.body_measurements
order by user_id, measurement, measured_at desc, created_at desc;
