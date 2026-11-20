-- Beta waitlist, written by the marketing website (body-comp-app-website).
-- The website inserts with the publishable key, so anon may INSERT only:
-- no select, update or delete for anyone but the service role. Duplicate
-- emails are ignored (ON CONFLICT DO NOTHING) so a signup never reveals
-- whether an address is already on the list.

create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique
    check (email = lower(email) and length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  platform text check (platform in ('ios', 'android')),
  dexa text check (dexa in ('bodyspec', 'other', 'none')),
  consent_version text not null check (length(consent_version) <= 32),
  source text not null default 'website' check (length(source) <= 64),
  created_at timestamptz not null default now()
);

comment on table public.waitlist is 'Beta waitlist signups from the marketing website. Insert-only for anon.';

alter table public.waitlist enable row level security;

revoke all on public.waitlist from anon, authenticated;
grant insert (email, platform, dexa, consent_version, source) on public.waitlist to anon, authenticated;

create policy "anyone can join the waitlist"
  on public.waitlist for insert
  to anon, authenticated
  with check (source = 'website');
