-- DEXA scans and the sync bookkeeping around them (LLD "DEXA provider sync",
-- build step 1). All masses are integer grams, lengths centimetres.
--
-- Who writes what:
--   provider_connections, sync_runs  the app, under RLS, for the signed-in user
--   raw_payloads, scans, scan_regions,
--   bone_density, percentiles        only ingest_normalized_scan, called by the
--                                    ingest-scan edge function with the service
--                                    role. Users can read and delete their own.
--   scans.photo_pair_status          the app (new-scan workflow), that column only

-- Provider links -------------------------------------------------------------

create table public.provider_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('bodyspec', 'fitnescity')),
  -- The provider's user id. Never a token: tokens stay on the phone.
  external_subject text check (char_length(external_subject) <= 200),
  status text not null default 'active'
    check (status in ('active', 'needs_reauth', 'revoked')),
  linked_at timestamptz not null default now(),
  last_synced_at timestamptz,
  last_error text check (char_length(last_error) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider),
  unique (id, user_id)
);

alter table public.provider_connections enable row level security;

create policy "provider_connections: owner can read"
  on public.provider_connections for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "provider_connections: owner can link"
  on public.provider_connections for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "provider_connections: owner can update"
  on public.provider_connections for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Disconnect sets status = revoked; rows go only with the account.
revoke update on public.provider_connections from anon, authenticated;
grant update (external_subject, status, linked_at, last_synced_at, last_error)
  on public.provider_connections to authenticated;

create trigger provider_connections_set_updated_at
  before update on public.provider_connections
  for each row execute function public.set_updated_at();

create table public.sync_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  connection_id uuid not null,
  kind text not null check (kind in ('first_import', 'refresh')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed')),
  scans_added int not null default 0 check (scans_added >= 0),
  error_code text check (char_length(error_code) <= 80),
  -- The connection must belong to the same user.
  foreign key (connection_id, user_id)
    references public.provider_connections (id, user_id) on delete cascade
);

create index sync_runs_connection_idx on public.sync_runs (connection_id, user_id, started_at desc);
create index sync_runs_user_idx on public.sync_runs (user_id);

alter table public.sync_runs enable row level security;

create policy "sync_runs: owner can read"
  on public.sync_runs for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "sync_runs: owner can start"
  on public.sync_runs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "sync_runs: owner can finish"
  on public.sync_runs for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke update on public.sync_runs from anon, authenticated;
grant update (finished_at, status, scans_added, error_code)
  on public.sync_runs to authenticated;

-- Raw source documents --------------------------------------------------------

create table public.raw_payloads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null check (source in ('bodyspec', 'manual', 'pdf', 'fitnescity')),
  provider_scan_id text check (char_length(provider_scan_id) <= 200),
  fetched_at timestamptz not null,
  payload jsonb,                  -- API sections, identity fields stripped
  storage_path text,              -- PDF uploads (pdf-uploads bucket)
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  check (payload is not null or storage_path is not null),
  unique (user_id, source, provider_scan_id, content_sha256)
);

alter table public.raw_payloads enable row level security;

create policy "raw_payloads: owner can read"
  on public.raw_payloads for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "raw_payloads: owner can delete"
  on public.raw_payloads for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update on public.raw_payloads from anon, authenticated;

-- Scans -----------------------------------------------------------------------

create table public.scans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null check (source in ('bodyspec', 'manual', 'pdf', 'fitnescity')),
  provider_scan_id text not null check (char_length(provider_scan_id) <= 200),
  scanned_at timestamptz not null,
  raw_payload_id uuid references public.raw_payloads (id) on delete set null,
  normalizer_version text not null check (char_length(normalizer_version) <= 40),
  status text not null default 'ok' check (status in ('ok', 'needs_review')),
  height_cm numeric(5, 1) check (height_cm > 0),
  weight_g int check (weight_g > 0),
  fat_g int check (fat_g >= 0),
  lean_g int check (lean_g >= 0),
  bone_g int check (bone_g >= 0),
  body_fat_pct numeric(4, 1) check (body_fat_pct between 0 and 100),
  vat_g int check (vat_g >= 0),
  android_gynoid_ratio numeric(4, 2) check (android_gynoid_ratio >= 0),
  rmr jsonb,                      -- BodySpec gives 4 formula estimates
  photo_pair_status text not null default 'pending'
    check (photo_pair_status in ('pending', 'done', 'skipped', 'expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, source, provider_scan_id),
  unique (id, user_id)
);

create index scans_user_scanned_at_idx on public.scans (user_id, scanned_at desc);
create index scans_raw_payload_idx on public.scans (raw_payload_id);

alter table public.scans enable row level security;

create policy "scans: owner can read"
  on public.scans for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "scans: owner can set photo pairing"
  on public.scans for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "scans: owner can delete"
  on public.scans for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update on public.scans from anon, authenticated;
grant update (photo_pair_status) on public.scans to authenticated;

create trigger scans_set_updated_at
  before update on public.scans
  for each row execute function public.set_updated_at();

-- Deleting a scan deletes its raw documents too: delete means delete.
create function public.delete_scan_raw_payloads()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.raw_payloads r
  where r.user_id = old.user_id
    and r.source = old.source
    and r.provider_scan_id = old.provider_scan_id;
  return old;
end;
$$;

create trigger scans_delete_raw_payloads
  after delete on public.scans
  for each row execute function public.delete_scan_raw_payloads();

create table public.scan_regions (
  scan_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  region text not null check (region in (
    'left_arm', 'right_arm', 'left_leg', 'right_leg', 'trunk', 'android', 'gynoid', 'head'
  )),
  lean_g int not null check (lean_g >= 0),
  fat_g int not null check (fat_g >= 0),
  bone_g int check (bone_g >= 0),
  fat_pct numeric(4, 1) check (fat_pct between 0 and 100),
  derived boolean not null default false,  -- true for head (total minus the rest)
  primary key (scan_id, region),
  foreign key (scan_id, user_id) references public.scans (id, user_id) on delete cascade
);

create index scan_regions_user_idx on public.scan_regions (user_id);
create index scan_regions_scan_user_idx on public.scan_regions (scan_id, user_id);

create table public.bone_density (
  scan_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  site text not null check (char_length(site) between 1 and 40),
  bmd_g_cm2 numeric(5, 3) check (bmd_g_cm2 >= 0),
  t_score numeric(3, 1),
  z_score numeric(3, 1),
  primary key (scan_id, site),
  foreign key (scan_id, user_id) references public.scans (id, user_id) on delete cascade
);

create index bone_density_user_idx on public.bone_density (user_id);
create index bone_density_scan_user_idx on public.bone_density (scan_id, user_id);

create table public.percentiles (
  scan_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  metric text not null check (char_length(metric) between 1 and 60),
  percentile numeric(4, 1) check (percentile between 0 and 100),
  band text check (band in ('green', 'yellow', 'red')),
  reference_group text check (char_length(reference_group) <= 80),
  primary key (scan_id, metric),
  foreign key (scan_id, user_id) references public.scans (id, user_id) on delete cascade
);

create index percentiles_user_idx on public.percentiles (user_id);
create index percentiles_scan_user_idx on public.percentiles (scan_id, user_id);

-- Read-only for users; ingest_normalized_scan replaces them with the scan.
alter table public.scan_regions enable row level security;
alter table public.bone_density enable row level security;
alter table public.percentiles enable row level security;

create policy "scan_regions: owner can read"
  on public.scan_regions for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "bone_density: owner can read"
  on public.bone_density for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "percentiles: owner can read"
  on public.percentiles for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.scan_regions, public.bone_density, public.percentiles
  from anon, authenticated;

-- Ingest ----------------------------------------------------------------------

-- Writes one normalized scan in a single transaction. Called only by the
-- ingest-scan edge function (service role), which takes p_user_id from the
-- verified JWT, strips identity fields, hashes and normalizes the payload.
--
-- p_raw  (null for manual entry):
--   {fetched_at, payload?, storage_path?, content_sha256}
-- p_scan:
--   {source, provider_scan_id, scanned_at, normalizer_version, status?,
--    height_cm?, weight_g?, fat_g?, lean_g?, bone_g?, body_fat_pct?, vat_g?,
--    android_gynoid_ratio?, rmr?,
--    regions: [{region, lean_g, fat_g, bone_g?, fat_pct?, derived?}],
--    bone_density: [{site, bmd_g_cm2?, t_score?, z_score?}],
--    percentiles: [{metric, percentile?, band?, reference_group?}]}
--
-- Returns {scan_id, status}: created, unchanged (same id and same raw hash) or
-- updated (same id, new hash: a new raw row is kept beside the old one).
create function public.ingest_normalized_scan(p_user_id uuid, p_raw jsonb, p_scan jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_source text := p_scan ->> 'source';
  v_provider_scan_id text := p_scan ->> 'provider_scan_id';
  v_existing_id uuid;
  v_existing_hash text;
  v_raw_id uuid;
  v_scan_id uuid;
  v_inserted boolean;
begin
  if p_user_id is null or v_source is null or v_provider_scan_id is null then
    raise exception 'user id, source and provider_scan_id are required'
      using errcode = '22023';
  end if;

  if not public.has_active_consent(p_user_id, 'health_data') then
    raise exception 'health_data consent required' using errcode = '42501';
  end if;

  select s.id, r.content_sha256
    into v_existing_id, v_existing_hash
  from public.scans s
  left join public.raw_payloads r on r.id = s.raw_payload_id
  where s.user_id = p_user_id
    and s.source = v_source
    and s.provider_scan_id = v_provider_scan_id
  for update of s;

  if v_existing_id is not null and p_raw is not null
     and v_existing_hash = p_raw ->> 'content_sha256' then
    return jsonb_build_object('scan_id', v_existing_id, 'status', 'unchanged');
  end if;

  if p_raw is not null then
    insert into public.raw_payloads
      (user_id, source, provider_scan_id, fetched_at, payload, storage_path, content_sha256)
    values (
      p_user_id, v_source, v_provider_scan_id,
      (p_raw ->> 'fetched_at')::timestamptz,
      p_raw -> 'payload',
      p_raw ->> 'storage_path',
      p_raw ->> 'content_sha256'
    )
    -- Reprocessed back to an earlier version: reuse that raw row.
    on conflict (user_id, source, provider_scan_id, content_sha256)
      do update set fetched_at = excluded.fetched_at
    returning id into v_raw_id;
  end if;

  insert into public.scans as s (
    user_id, source, provider_scan_id, scanned_at, raw_payload_id,
    normalizer_version, status, height_cm, weight_g, fat_g, lean_g, bone_g,
    body_fat_pct, vat_g, android_gynoid_ratio, rmr
  )
  values (
    p_user_id, v_source, v_provider_scan_id,
    (p_scan ->> 'scanned_at')::timestamptz,
    v_raw_id,
    p_scan ->> 'normalizer_version',
    coalesce(p_scan ->> 'status', 'ok'),
    (p_scan ->> 'height_cm')::numeric,
    (p_scan ->> 'weight_g')::int,
    (p_scan ->> 'fat_g')::int,
    (p_scan ->> 'lean_g')::int,
    (p_scan ->> 'bone_g')::int,
    (p_scan ->> 'body_fat_pct')::numeric,
    (p_scan ->> 'vat_g')::int,
    (p_scan ->> 'android_gynoid_ratio')::numeric,
    p_scan -> 'rmr'
  )
  on conflict (user_id, source, provider_scan_id) do update set
    scanned_at = excluded.scanned_at,
    raw_payload_id = coalesce(excluded.raw_payload_id, s.raw_payload_id),
    normalizer_version = excluded.normalizer_version,
    status = excluded.status,
    height_cm = excluded.height_cm,
    weight_g = excluded.weight_g,
    fat_g = excluded.fat_g,
    lean_g = excluded.lean_g,
    bone_g = excluded.bone_g,
    body_fat_pct = excluded.body_fat_pct,
    vat_g = excluded.vat_g,
    android_gynoid_ratio = excluded.android_gynoid_ratio,
    rmr = excluded.rmr
  returning s.id, (s.xmax = 0) into v_scan_id, v_inserted;

  delete from public.scan_regions where scan_id = v_scan_id;
  insert into public.scan_regions (scan_id, user_id, region, lean_g, fat_g, bone_g, fat_pct, derived)
  select v_scan_id, p_user_id, x.region, x.lean_g, x.fat_g, x.bone_g, x.fat_pct,
         coalesce(x.derived, false)
  from jsonb_to_recordset(coalesce(p_scan -> 'regions', '[]'))
    as x (region text, lean_g int, fat_g int, bone_g int, fat_pct numeric, derived boolean);

  delete from public.bone_density where scan_id = v_scan_id;
  insert into public.bone_density (scan_id, user_id, site, bmd_g_cm2, t_score, z_score)
  select v_scan_id, p_user_id, x.site, x.bmd_g_cm2, x.t_score, x.z_score
  from jsonb_to_recordset(coalesce(p_scan -> 'bone_density', '[]'))
    as x (site text, bmd_g_cm2 numeric, t_score numeric, z_score numeric);

  delete from public.percentiles where scan_id = v_scan_id;
  insert into public.percentiles (scan_id, user_id, metric, percentile, band, reference_group)
  select v_scan_id, p_user_id, x.metric, x.percentile, x.band, x.reference_group
  from jsonb_to_recordset(coalesce(p_scan -> 'percentiles', '[]'))
    as x (metric text, percentile numeric, band text, reference_group text);

  return jsonb_build_object(
    'scan_id', v_scan_id,
    'status', case when v_inserted then 'created' else 'updated' end
  );
end;
$$;

revoke execute on function public.ingest_normalized_scan(uuid, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_normalized_scan(uuid, jsonb, jsonb) to service_role;
