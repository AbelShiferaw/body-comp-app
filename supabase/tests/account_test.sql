-- pgTAP tests for profile fields and account deletion. Run: supabase test db
begin;
select plan(11);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

select is(
  (select units from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'imperial',
  'new profiles default to imperial units'
);

-- Act as Alice.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok(
  $$ update public.profiles
     set sex = 'female', birth_year = 1990, height_cm = 168.5, units = 'imperial'
     where id = '11111111-1111-1111-1111-111111111111' $$,
  'Alice can fill in her profile'
);

select is(
  (select height_cm from public.profiles),
  168.5::numeric,
  'height keeps one decimal'
);

select throws_ok(
  $$ update public.profiles set sex = 'other' $$,
  '23514', null, 'sex must be male or female'
);

select throws_ok(
  $$ update public.profiles set height_cm = 40 $$,
  '23514', null, 'height must be realistic'
);

select throws_ok(
  $$ update public.profiles set birth_year = 1800 $$,
  '23514', null, 'birth year must be realistic'
);

-- Signed out users cannot delete anything.
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$ select public.delete_account() $$,
  '42501', null, 'anonymous users cannot call delete_account'
);

-- Alice deletes her account.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok($$ select public.delete_account() $$, 'Alice can delete her account');

reset role;

select is(
  (select count(*)::int from auth.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Alice''s auth user is gone'
);

select is(
  (select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'and her profile went with it'
);

select is(
  (select count(*)::int from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  1,
  'Bob''s profile is untouched'
);

select * from finish();
rollback;
