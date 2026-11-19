-- BodySpec sync beta gate and onboarding answers (v1 build step 2).
--
-- BodySpec's terms bar commercial and automated use without an agreement, so
-- BodySpec sync runs behind a server-side flag and an invite allowlist until a
-- partner agreement exists (LLD "DEXA provider sync"). The app asks
-- feature_enabled('bodyspec_sync') before linking, and the ingest-scan edge
-- function checks feature_enabled_for(user, 'bodyspec_sync') before writing.
--
-- To let someone in (SQL editor, as the project owner):
--   update public.feature_flags set enabled = true where key = 'bodyspec_sync';
--   insert into public.feature_allowlist (feature, user_id)
--     select 'bodyspec_sync', id from auth.users where email = '<their email>';

-- Feature flags -----------------------------------------------------------------

create table public.feature_flags (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  enabled boolean not null default false,
  -- When true, only users on feature_allowlist get the feature.
  invite_only boolean not null default true,
  updated_at timestamptz not null default now()
);

-- Users never read the tables directly: they ask feature_enabled() about
-- themselves, so nobody can list who else is in a beta.
alter table public.feature_flags enable row level security;
revoke all on public.feature_flags from anon, authenticated;

create trigger feature_flags_set_updated_at
  before update on public.feature_flags
  for each row execute function public.set_updated_at();

create table public.feature_allowlist (
  feature text not null references public.feature_flags (key) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (feature, user_id)
);

create index feature_allowlist_user_idx on public.feature_allowlist (user_id);

alter table public.feature_allowlist enable row level security;
revoke all on public.feature_allowlist from anon, authenticated;

insert into public.feature_flags (key, enabled, invite_only)
values ('bodyspec_sync', false, true);

-- True when the feature is on for this user: the flag is enabled and, if it
-- is invite-only, the user is on its allowlist. Unknown features are off.
create function public.feature_enabled_for(p_user_id uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select f.enabled and (
      not f.invite_only or exists (
        select 1 from public.feature_allowlist a
        where a.feature = f.key and a.user_id = p_user_id
      )
    )
    from public.feature_flags f
    where f.key = p_feature
  ), false);
$$;

-- Service role only (edge functions), so a user cannot probe other users.
revoke execute on function public.feature_enabled_for(uuid, text)
  from public, anon, authenticated;
grant execute on function public.feature_enabled_for(uuid, text) to service_role;

-- The caller's own answer. What the app calls.
create function public.feature_enabled(p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.feature_enabled_for((select auth.uid()), p_feature);
$$;

revoke execute on function public.feature_enabled(text) from public, anon;
grant execute on function public.feature_enabled(text) to authenticated;

-- Onboarding --------------------------------------------------------------------

alter table public.profiles
  -- What the user wants from the app, from the onboarding quiz. Shapes the
  -- copy and the metrics we lead with, nothing else.
  add column goals text[] not null default '{}'
    check (
      goals <@ array['lose_fat', 'build_muscle', 'track_health']::text[]
      and cardinality(goals) <= 3
    ),
  -- How the user chose to build their body: a DEXA provider or photos.
  add column body_source text check (body_source in ('dexa', 'photos')),
  -- Set when the user finishes onboarding (the first look at their body).
  -- Until then the app keeps them in onboarding.
  add column onboarded_at timestamptz;

comment on column public.profiles.goals is
  'Onboarding quiz answers: lose_fat, build_muscle, track_health.';
comment on column public.profiles.onboarded_at is
  'When onboarding finished. Null keeps the user in onboarding.';
