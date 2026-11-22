-- pgTAP: DEXA scan tables. Ingest behaviour (created / unchanged / updated,
-- all-or-nothing) and row level security: one user can never read or change
-- another user's scans, regions, raw payloads, connections or sync runs.
-- Run: supabase test db
begin;
select plan(50);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

insert into public.consents (user_id, kind, document_version)
values ('11111111-1111-1111-1111-111111111111', 'health_data', 'v1');

-- A normalized scan with all eight regions, as the edge function sends it.
create temporary table fixture (scan jsonb) on commit drop;
insert into fixture values ($json${
  "source": "bodyspec",
  "provider_scan_id": "scan-a",
  "scanned_at": "2026-11-01T15:00:00Z",
  "normalizer_version": "bodyspec-n1",
  "height_cm": 180.3, "weight_g": 80000,
  "fat_g": 12000, "lean_g": 64500, "bone_g": 3500, "body_fat_pct": 15.0,
  "vat_g": 300, "android_gynoid_ratio": 0.85,
  "rmr": {"cunningham": 1900},
  "regions": [
    {"region": "left_arm",  "lean_g": 4000,  "fat_g": 600,  "bone_g": 200, "fat_pct": 12.5},
    {"region": "right_arm", "lean_g": 4100,  "fat_g": 610,  "bone_g": 210, "fat_pct": 12.4},
    {"region": "left_leg",  "lean_g": 11000, "fat_g": 2000, "bone_g": 600, "fat_pct": 14.7},
    {"region": "right_leg", "lean_g": 11100, "fat_g": 2010, "bone_g": 610, "fat_pct": 14.6},
    {"region": "trunk",     "lean_g": 30000, "fat_g": 6000, "bone_g": 900, "fat_pct": 16.3},
    {"region": "android",   "lean_g": 4000,  "fat_g": 900,  "fat_pct": 18.4},
    {"region": "gynoid",    "lean_g": 8000,  "fat_g": 1800, "fat_pct": 18.4},
    {"region": "head",      "lean_g": 4300,  "fat_g": 780,  "derived": true}
  ],
  "bone_density": [{"site": "total", "bmd_g_cm2": 1.312, "t_score": 1.4, "z_score": 1.2}],
  "percentiles": [{"metric": "body_fat_pct", "percentile": 80, "band": "green"}]
}$json$);
grant select on fixture to authenticated, service_role;

create function pg_temp.raw(p_hash text) returns jsonb language sql as $$
  select jsonb_build_object(
    'fetched_at', '2026-11-02T00:00:00Z',
    'payload', '{"composition": {}}'::jsonb,
    'content_sha256', p_hash);
$$;

-- RLS on every table --------------------------------------------------------
select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.consents'::regclass, 'public.provider_connections'::regclass,
                 'public.sync_runs'::regclass, 'public.raw_payloads'::regclass,
                 'public.scans'::regclass, 'public.scan_regions'::regclass,
                 'public.bone_density'::regclass, 'public.percentiles'::regclass)),
  'RLS is enabled on every scan and sync table'
);

-- Ingest --------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok(
  $$ select public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111', null, (select scan from fixture)) $$,
  '42501', 'permission denied for function ingest_normalized_scan',
  'the app cannot call ingest_normalized_scan'
);

select throws_ok(
  $$ insert into public.scans (user_id, source, provider_scan_id, scanned_at, normalizer_version)
     values ('11111111-1111-1111-1111-111111111111', 'manual', 'x', now(), 'n') $$,
  '42501', 'permission denied for table scans',
  'users cannot insert scans directly'
);

select throws_ok(
  $$ insert into public.raw_payloads (user_id, source, fetched_at, payload, content_sha256)
     values ('11111111-1111-1111-1111-111111111111', 'manual', now(), '{}', repeat('a', 64)) $$,
  '42501', 'permission denied for table raw_payloads',
  'users cannot insert raw payloads directly'
);

reset role;
set local role service_role;

select throws_ok(
  $$ select public.ingest_normalized_scan('22222222-2222-2222-2222-222222222222', null,
       (select scan from fixture)) $$,
  '42501', 'health_data consent required',
  'ingest refuses a user without health-data consent'
);

select is(
  public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111',
    pg_temp.raw(repeat('a', 64)), (select scan from fixture)) ->> 'status',
  'created',
  'first ingest creates the scan'
);

select is(
  public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111',
    pg_temp.raw(repeat('a', 64)), (select scan from fixture)) ->> 'status',
  'unchanged',
  'same scan and same hash is unchanged'
);

select is(
  public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111',
    pg_temp.raw(repeat('a', 64)),
    (select jsonb_set(scan, '{normalizer_version}', '"bodyspec-n2"') from fixture)) ->> 'status',
  'updated',
  'same raw with a new normalizer version is rewritten'
);

select is(
  public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111',
    pg_temp.raw(repeat('b', 64)),
    (select jsonb_set(scan, '{fat_g}', '11000') from fixture)) ->> 'status',
  'updated',
  'same scan with a new hash is updated'
);

select throws_ok(
  $$ select public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111',
       pg_temp.raw(repeat('c', 64)),
       (select jsonb_set(jsonb_set(scan, '{provider_scan_id}', '"scan-bad"'),
          '{regions,0,region}', '"tail"') from fixture)) $$,
  '23514', null,
  'a scan with an unknown region is rejected'
);

reset role;

select is((select count(*)::int from public.scans), 1, 'one scan row after three ingests and a failure');
select is((select fat_g from public.scans), 11000, 'the update rewrote the scan values');
select is((select count(*)::int from public.raw_payloads), 2, 'both raw versions are kept');
select is((select count(*)::int from public.raw_payloads where provider_scan_id = 'scan-bad'), 0,
  'the failed ingest left no raw payload behind');
select is((select count(*)::int from public.scan_regions), 8, 'regions were replaced, not duplicated');
select is((select count(*)::int from public.bone_density), 1, 'bone density stored');
select is((select count(*)::int from public.percentiles), 1, 'percentiles stored');
select is((select derived from public.scan_regions where region = 'head'), true, 'head is marked derived');

-- Alice: her own rows ------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*)::int from public.scans), 1, 'Alice sees her scan');
select is((select count(*)::int from public.scan_regions), 8, 'Alice sees her regions');

update public.scans set photo_pair_status = 'skipped';
select is((select photo_pair_status from public.scans), 'skipped', 'Alice can set photo pairing');

select throws_ok(
  $$ update public.scans set fat_g = 1 $$,
  '42501', null,
  'Alice cannot edit scan values'
);

select throws_ok(
  $$ update public.scan_regions set fat_g = 1 $$,
  '42501', null,
  'Alice cannot edit region values'
);

insert into public.provider_connections (id, user_id, provider, external_subject)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'bodyspec', 'bs-alice');

insert into public.sync_runs (id, user_id, connection_id, kind)
values ('aaaaaaaa-0000-0000-0000-0000000000f1', '11111111-1111-1111-1111-111111111111',
        'aaaaaaaa-0000-0000-0000-000000000001', 'first_import');

update public.sync_runs set status = 'succeeded', scans_added = 1, finished_at = now();
select is((select status from public.sync_runs), 'succeeded', 'Alice can finish her sync run');

update public.provider_connections set status = 'needs_reauth', last_error = 'invalid_grant';
select is((select status from public.provider_connections), 'needs_reauth', 'Alice can update her connection status');

select throws_ok(
  $$ update public.provider_connections set provider = 'fitnescity' $$,
  '42501', null,
  'Alice cannot change which provider a connection is for'
);

-- Bob: nothing of Alice's ---------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*)::int from public.scans), 0, 'Bob sees no scans');
select is((select count(*)::int from public.scan_regions), 0, 'Bob sees no regions');
select is((select count(*)::int from public.raw_payloads), 0, 'Bob sees no raw payloads');
select is((select count(*)::int from public.bone_density), 0, 'Bob sees no bone density');
select is((select count(*)::int from public.percentiles), 0, 'Bob sees no percentiles');
select is((select count(*)::int from public.provider_connections), 0, 'Bob sees no connections');
select is((select count(*)::int from public.sync_runs), 0, 'Bob sees no sync runs');
select is((select count(*)::int from public.consents), 0, 'Bob sees no consents');

select is_empty(
  $$ update public.scans set photo_pair_status = 'done' returning id $$,
  'Bob cannot change Alice''s scan'
);
select is_empty($$ delete from public.scans returning id $$, 'Bob cannot delete Alice''s scan');
select is_empty($$ delete from public.raw_payloads returning id $$, 'Bob cannot delete Alice''s raw payloads');
select is_empty(
  $$ update public.provider_connections set status = 'revoked' returning id $$,
  'Bob cannot change Alice''s connection'
);
select is_empty(
  $$ update public.sync_runs set status = 'failed' returning id $$,
  'Bob cannot change Alice''s sync runs'
);
select is_empty(
  $$ update public.consents set revoked_at = now() returning id $$,
  'Bob cannot revoke Alice''s consent'
);

select throws_ok(
  $$ insert into public.provider_connections (user_id, provider)
     values ('11111111-1111-1111-1111-111111111111', 'fitnescity') $$,
  '42501', null,
  'Bob cannot create a connection for Alice'
);

select throws_ok(
  $$ insert into public.sync_runs (user_id, connection_id, kind)
     values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001', 'refresh') $$,
  '23503', null,
  'Bob cannot log a sync run against Alice''s connection'
);

select throws_ok(
  $$ insert into public.consents (user_id, kind, document_version)
     values ('11111111-1111-1111-1111-111111111111', 'model_training', 'v1') $$,
  '42501', null,
  'Bob cannot grant consent for Alice'
);

-- Signed out ----------------------------------------------------------------
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is((select count(*)::int from public.scans), 0, 'anonymous users see no scans');

-- Alice deletes her scan: everything about it goes ---------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok(
  $$ update public.consents set kind = 'terms' $$,
  '42501', null,
  'Alice cannot rewrite what she consented to'
);

update public.consents set revoked_at = '2000-01-01' where kind = 'health_data';
select ok(
  (select revoked_at > now() - interval '1 minute' from public.consents where kind = 'health_data'),
  'revoking stamps the current time, not a backdated one'
);
select is_empty(
  $$ update public.consents set revoked_at = null returning id $$,
  'a revoked consent cannot be brought back'
);

delete from public.scans;

reset role;
select is((select count(*)::int from public.scans), 0, 'Alice deleted her scan');
select is((select count(*)::int from public.scan_regions), 0, 'its regions went with it');
select is((select count(*)::int from public.raw_payloads), 0, 'its raw payloads went with it');

select * from finish();
rollback;
