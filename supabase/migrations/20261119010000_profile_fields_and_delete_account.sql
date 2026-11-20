-- Profile fields the 3D body and the scan mapping need, and account deletion.
--
-- We keep the least data that works: birth year instead of a birth date, and
-- no name. Sex is the body model's base shape (the DEXA reference sets are
-- male/female), not a gender identity field.

alter table public.profiles
  add column sex text check (sex in ('male', 'female')),
  -- The app also rejects future years and under-13s; the bounds here only
  -- stop nonsense values.
  add column birth_year smallint check (birth_year between 1900 and 2100),
  add column height_cm numeric(4, 1) check (height_cm between 100 and 250),
  add column units text not null default 'metric'
    check (units in ('metric', 'imperial'));

comment on column public.profiles.sex is
  'Body model base shape: male or female. Null until profile setup.';
comment on column public.profiles.units is
  'Display units only. Everything is stored metric.';

-- Deletes the caller's account. The auth user's deletion cascades to every
-- user-owned table (each references auth.users (id) on delete cascade).
-- Runs as the function owner because users cannot delete auth.users rows.
-- When private Storage buckets arrive, move this to an edge function that also
-- removes the user's files.
create function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from auth.users where id = uid;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
