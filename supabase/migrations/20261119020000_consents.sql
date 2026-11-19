-- Consents (HLD "Security, privacy and consent"). One row per consent given;
-- revoking sets revoked_at instead of deleting, so we can prove what a user
-- agreed to and when. ingest_normalized_scan refuses scans without an active
-- health_data consent.

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null
    check (kind in ('terms', 'privacy', 'health_data', 'model_training')),
  document_version text not null check (char_length(document_version) between 1 and 40),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (revoked_at is null or revoked_at >= granted_at)
);

create index consents_user_kind_idx on public.consents (user_id, kind);

alter table public.consents enable row level security;

create policy "consents: owner can read"
  on public.consents for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "consents: owner can grant"
  on public.consents for insert
  to authenticated
  with check ((select auth.uid()) = user_id and revoked_at is null);

-- Revoking is one-way: only an active consent can be updated, and only to
-- revoked. The trigger below stamps the time, so it cannot be backdated.
create policy "consents: owner can revoke"
  on public.consents for update
  to authenticated
  using ((select auth.uid()) = user_id and revoked_at is null)
  with check ((select auth.uid()) = user_id and revoked_at is not null);

-- Only revoked_at may change; the rest is the record of what was agreed.
revoke update on public.consents from anon, authenticated;
grant update (revoked_at) on public.consents to authenticated;

create function public.stamp_consent_revoked_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.revoked_at is not null then
    raise exception 'consent already revoked' using errcode = '42501';
  end if;
  if new.revoked_at is not null then
    new.revoked_at = now();
  end if;
  return new;
end;
$$;

create trigger consents_stamp_revoked_at
  before update on public.consents
  for each row execute function public.stamp_consent_revoked_at();

-- No delete policy: consents go only with the account (cascade).

-- True when the user has an unrevoked consent of this kind.
create function public.has_active_consent(p_user_id uuid, p_kind text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.consents c
    where c.user_id = p_user_id and c.kind = p_kind and c.revoked_at is null
  );
$$;

-- Internal: called by ingest_normalized_scan. Not callable from the app, so a
-- user cannot probe another user's consents.
revoke execute on function public.has_active_consent(uuid, text) from public, anon, authenticated;
grant execute on function public.has_active_consent(uuid, text) to service_role;
