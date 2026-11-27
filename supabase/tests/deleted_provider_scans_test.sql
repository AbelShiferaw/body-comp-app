-- pgTAP: a deleted provider scan is remembered (ids only) so Refresh does
-- not import it again; only its owner can see that, nobody can write it,
-- and deleting the account removes it. Run: supabase test db
begin;
select plan(10);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

insert into public.consents (user_id, kind, document_version)
values ('11111111-1111-1111-1111-111111111111', 'health_data', 'v1');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.deleted_provider_scans'::regclass),
  'RLS is enabled on deleted_provider_scans'
);

set local role service_role;
select public.ingest_normalized_scan(
  '11111111-1111-1111-1111-111111111111',
  jsonb_build_object(
    'fetched_at', '2026-11-02T00:00:00Z',
    'payload', '{"composition": {}}'::jsonb,
    'content_sha256', repeat('a', 64)),
  $json${
    "source": "bodyspec", "provider_scan_id": "scan-a",
    "scanned_at": "2026-11-01T15:00:00Z", "normalizer_version": "bodyspec-n1",
    "fat_g": 12000, "lean_g": 64500, "regions": [],
    "bone_density": [], "percentiles": []
  }$json$::jsonb
);
reset role;

-- Alice deletes her scan.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is_empty(
  $$ select 1 from public.deleted_provider_scans $$,
  'nothing is remembered before a delete'
);
delete from public.scans;
select results_eq(
  $$ select source, provider_scan_id from public.deleted_provider_scans $$,
  $$ values ('bodyspec'::text, 'scan-a'::text) $$,
  'Alice sees the scan she deleted, so sync treats it as known'
);
select throws_ok(
  $$ insert into public.deleted_provider_scans (user_id, source, provider_scan_id)
     values ('11111111-1111-1111-1111-111111111111', 'bodyspec', 'scan-b') $$,
  '42501', null,
  'the app cannot add tombstones'
);
select throws_ok(
  $$ delete from public.deleted_provider_scans $$,
  '42501', null,
  'the app cannot remove tombstones (that would bring the scan back)'
);
select throws_ok(
  $$ select public.remember_deleted_provider_scan() $$,
  '42501', null,
  'the app cannot call the trigger function'
);

-- Bob sees none of it.
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is_empty(
  $$ select 1 from public.deleted_provider_scans $$,
  'Bob cannot see Alice''s deleted scans'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$ select 1 from public.deleted_provider_scans $$,
  '42501', null,
  'anonymous users cannot read deleted scans'
);

-- Deleting the account removes the tombstones, even with scans still there.
reset role;
set local role service_role;
select public.ingest_normalized_scan(
  '11111111-1111-1111-1111-111111111111',
  jsonb_build_object(
    'fetched_at', '2026-11-02T00:00:00Z',
    'payload', '{"composition": {}}'::jsonb,
    'content_sha256', repeat('b', 64)),
  $json${
    "source": "bodyspec", "provider_scan_id": "scan-c",
    "scanned_at": "2026-11-05T15:00:00Z", "normalizer_version": "bodyspec-n1",
    "fat_g": 12000, "lean_g": 64500, "regions": [],
    "bone_density": [], "percentiles": []
  }$json$::jsonb
);
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select lives_ok($$ select public.delete_account() $$, 'Alice can delete her account with a scan left');
reset role;
select is(
  (select count(*)::int from public.deleted_provider_scans),
  0,
  'deleting the account leaves no tombstones'
);

select * from finish();
