-- pgTAP: photo sessions and body measurements. Raw photo paths need a
-- model_training consent, a tape edit overrides the photo value until the next
-- session, and one user can never read or change another's rows.
-- Run: supabase test db
begin;
select plan(17);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

insert into public.consents (user_id, kind, document_version)
values ('11111111-1111-1111-1111-111111111111', 'health_data', 'v1');

set local role service_role;
select public.ingest_normalized_scan('11111111-1111-1111-1111-111111111111', null, $json${
  "source": "manual", "provider_scan_id": "m1", "scanned_at": "2026-11-01T15:00:00Z",
  "normalizer_version": "manual-n1", "body_fat_pct": 15.0
}$json$);
reset role;
create temporary table alice_scan on commit drop as select id from public.scans;
grant select on alice_scan to authenticated;

select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.photo_sessions'::regclass, 'public.body_measurements'::regclass)),
  'RLS is enabled on photo sessions and measurements'
);

select is(
  (select reloptions from pg_class where oid = 'public.current_body_measurements'::regclass),
  array['security_invoker=true'],
  'current_body_measurements runs with the caller''s RLS'
);

-- Alice ----------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok(
  $$ insert into public.photo_sessions (user_id, storage_paths)
     values ('11111111-1111-1111-1111-111111111111', array['training-photos/a/front.jpg']) $$,
  '42501', null,
  'raw photos cannot be stored without a model_training consent'
);

insert into public.photo_sessions (id, user_id, captured_at, sdk, paired_scan_id)
values ('aaaaaaaa-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111',
        '2026-11-02T10:00:00Z', 'on_device',
        (select id from public.scans));
select is((select count(*)::int from public.photo_sessions), 1, 'Alice can save a photo session paired to her scan');

insert into public.body_measurements (user_id, measurement, value_cm, source, photo_session_id, measured_at)
values
  ('11111111-1111-1111-1111-111111111111', 'waist', 82.0, 'photo', 'aaaaaaaa-0000-0000-0000-0000000000a1', '2026-11-02T10:00:00Z'),
  ('11111111-1111-1111-1111-111111111111', 'chest', 101.0, 'photo', 'aaaaaaaa-0000-0000-0000-0000000000a1', '2026-11-02T10:00:00Z');

insert into public.body_measurements (user_id, measurement, value_cm, source, measured_at)
values ('11111111-1111-1111-1111-111111111111', 'waist', 80.5, 'tape', '2026-11-03T08:00:00Z');

select is(
  (select value_cm from public.current_body_measurements where measurement = 'waist'),
  80.5,
  'a tape edit overrides the photo value'
);
select is(
  (select value_cm from public.current_body_measurements where measurement = 'chest'),
  101.0,
  'other photo values stay current'
);

insert into public.photo_sessions (id, user_id, captured_at)
values ('aaaaaaaa-0000-0000-0000-0000000000a2', '11111111-1111-1111-1111-111111111111', '2026-11-10T10:00:00Z');
insert into public.body_measurements (user_id, measurement, value_cm, source, photo_session_id, measured_at)
values ('11111111-1111-1111-1111-111111111111', 'waist', 79.0, 'photo', 'aaaaaaaa-0000-0000-0000-0000000000a2', '2026-11-10T10:00:00Z');

select is(
  (select value_cm from public.current_body_measurements where measurement = 'waist'),
  79.0,
  'the next photo session replaces the tape edit'
);

select throws_ok(
  $$ insert into public.body_measurements (user_id, measurement, value_cm, source)
     values ('11111111-1111-1111-1111-111111111111', 'waist', 80, 'photo') $$,
  '23514', null,
  'a photo measurement needs its session'
);

select throws_ok(
  $$ insert into public.body_measurements (user_id, measurement, value_cm, source)
     values ('11111111-1111-1111-1111-111111111111', 'nose', 3, 'tape') $$,
  '23514', null,
  'unknown measurement keys are rejected'
);

-- Bob ------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*)::int from public.photo_sessions), 0, 'Bob sees no photo sessions');
select is((select count(*)::int from public.body_measurements), 0, 'Bob sees no measurements');
select is((select count(*)::int from public.current_body_measurements), 0, 'Bob sees no current measurements');

select is_empty(
  $$ update public.body_measurements set value_cm = 1 returning id $$,
  'Bob cannot change Alice''s measurements'
);
select is_empty($$ delete from public.photo_sessions returning id $$, 'Bob cannot delete Alice''s sessions');

select throws_ok(
  $$ insert into public.photo_sessions (user_id, paired_scan_id)
     values ('22222222-2222-2222-2222-222222222222',
             (select id from alice_scan)) $$,
  '23503', null,
  'Bob cannot pair a session with Alice''s scan'
);

select throws_ok(
  $$ insert into public.body_measurements (user_id, measurement, value_cm, source, photo_session_id)
     values ('22222222-2222-2222-2222-222222222222', 'waist', 70, 'photo',
             'aaaaaaaa-0000-0000-0000-0000000000a1') $$,
  '23503', null,
  'Bob cannot attach measurements to Alice''s session'
);

-- Deleting a session deletes its measurements --------------------------------
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
delete from public.photo_sessions where id = 'aaaaaaaa-0000-0000-0000-0000000000a2';
select is(
  (select value_cm from public.current_body_measurements where measurement = 'waist'),
  80.5,
  'deleting a session falls back to the previous value'
);

select * from finish();
rollback;
