-- pgTAP: the BodySpec beta gate and the onboarding profile columns.
-- Users can ask about themselves only; nobody can list the flags or the
-- allowlist, or add themselves to a beta.
-- Run: supabase test db
begin;
select plan(17);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.feature_flags'::regclass, 'public.feature_allowlist'::regclass)),
  'RLS is enabled on the flag tables'
);

select is(
  (select enabled from public.feature_flags where key = 'bodyspec_sync'),
  false,
  'BodySpec sync ships switched off'
);

-- Flag off: nobody gets it, allowlisted or not.
insert into public.feature_allowlist (feature, user_id)
values ('bodyspec_sync', '11111111-1111-1111-1111-111111111111');
select is(
  public.feature_enabled_for('11111111-1111-1111-1111-111111111111', 'bodyspec_sync'),
  false, 'off for an allowlisted user while the flag is off'
);

update public.feature_flags set enabled = true where key = 'bodyspec_sync';
select is(
  public.feature_enabled_for('11111111-1111-1111-1111-111111111111', 'bodyspec_sync'),
  true, 'on for an allowlisted user once the flag is on'
);
select is(
  public.feature_enabled_for('22222222-2222-2222-2222-222222222222', 'bodyspec_sync'),
  false, 'still off for a user who is not invited'
);
select is(
  public.feature_enabled_for('11111111-1111-1111-1111-111111111111', 'no_such_feature'),
  false, 'unknown features are off'
);

-- As the users themselves ----------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select is(public.feature_enabled('bodyspec_sync'), true, 'alice sees she is in the beta');
select throws_ok(
  $$select public.feature_enabled_for('22222222-2222-2222-2222-222222222222', 'bodyspec_sync')$$,
  '42501', null, 'users cannot ask about someone else'
);
select throws_ok(
  $$select * from public.feature_allowlist$$,
  '42501', null, 'users cannot list the allowlist'
);
select throws_ok(
  $$select * from public.feature_flags$$,
  '42501', null, 'users cannot read the flags table'
);

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.feature_enabled('bodyspec_sync'), false, 'bob sees he is not');
select throws_ok(
  $$insert into public.feature_allowlist (feature, user_id)
    values ('bodyspec_sync', '22222222-2222-2222-2222-222222222222')$$,
  '42501', null, 'users cannot invite themselves'
);
select throws_ok(
  $$update public.feature_flags set invite_only = false$$,
  '42501', null, 'users cannot open the beta to everyone'
);

-- Onboarding columns -----------------------------------------------------------
select lives_ok(
  $$update public.profiles
    set goals = array['lose_fat', 'build_muscle'], body_source = 'dexa', onboarded_at = now()
    where id = '22222222-2222-2222-2222-222222222222'$$,
  'a user saves their onboarding answers'
);
select throws_ok(
  $$update public.profiles set goals = array['get_famous']
    where id = '22222222-2222-2222-2222-222222222222'$$,
  '23514', null, 'unknown goals are rejected'
);
select throws_ok(
  $$update public.profiles set body_source = 'guess'
    where id = '22222222-2222-2222-2222-222222222222'$$,
  '23514', null, 'unknown body sources are rejected'
);

update public.profiles set onboarded_at = now()
  where id = '11111111-1111-1111-1111-111111111111';
reset role;
select is(
  (select onboarded_at from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  null, 'bob cannot finish onboarding for alice (her row is untouched)'
);

select * from finish();
rollback;
