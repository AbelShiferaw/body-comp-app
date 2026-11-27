-- Beta waitlist, written by the marketing website (body-comp-app-website).
-- Nobody but the service role can touch the table directly. The website
-- calls join_waitlist() with the publishable key; it ignores duplicate
-- emails so a signup never reveals whether an address is already listed.

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

comment on table public.waitlist is 'Beta waitlist signups from the marketing website. Written only via join_waitlist().';

-- RLS on with no policies: anon and authenticated get nothing.
alter table public.waitlist enable row level security;
revoke all on public.waitlist from anon, authenticated;

create function public.join_waitlist(
  p_email text,
  p_platform text default null,
  p_dexa text default null,
  p_consent_version text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.waitlist (email, platform, dexa, consent_version, source)
  values (lower(trim(p_email)), p_platform, p_dexa, p_consent_version, 'website')
  on conflict (email) do nothing;
$$;

comment on function public.join_waitlist is 'Adds an email to the beta waitlist; duplicates are ignored. Called by the website.';

revoke all on function public.join_waitlist(text, text, text, text) from public;
grant execute on function public.join_waitlist(text, text, text, text) to anon, authenticated;
