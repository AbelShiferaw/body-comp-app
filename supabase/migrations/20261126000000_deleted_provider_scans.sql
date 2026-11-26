-- Deleted provider scans stay deleted.
--
-- Sync imports every provider scan it does not know yet, and "known" comes
-- from public.scans. Deleting a scan removes its row and raw payloads, so
-- without a record of the deletion the next Refresh would import it again.
-- This table remembers which provider scans a user deleted (ids only, no
-- body data), and the app counts them as known.
--
-- Written only by the scans delete trigger; the owner can read their rows.
-- Deleting the account removes them with the user.

create table public.deleted_provider_scans (
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null check (source in ('bodyspec', 'manual', 'pdf', 'fitnescity')),
  provider_scan_id text not null check (char_length(provider_scan_id) <= 200),
  deleted_at timestamptz not null default now(),
  primary key (user_id, source, provider_scan_id)
);

alter table public.deleted_provider_scans enable row level security;

create policy "deleted_provider_scans: owner can read"
  on public.deleted_provider_scans for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.deleted_provider_scans from anon, authenticated;
grant select on public.deleted_provider_scans to authenticated;

-- Security definer because the app may delete scans but never write this
-- table. Skipped while the account itself is being deleted (the user row is
-- already gone, and the tombstone would go with it anyway).
create function public.remember_deleted_provider_scan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from auth.users u where u.id = old.user_id) then
    insert into public.deleted_provider_scans (user_id, source, provider_scan_id)
    values (old.user_id, old.source, old.provider_scan_id)
    on conflict do nothing;
  end if;
  return old;
end;
$$;

revoke execute on function public.remember_deleted_provider_scan() from public, anon, authenticated;

create trigger scans_remember_deleted
  after delete on public.scans
  for each row execute function public.remember_deleted_provider_scan();
