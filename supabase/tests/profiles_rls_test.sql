-- pgTAP tests for row level security. Run: supabase test db
begin;
select plan(7);

-- Two users. Inserting into auth.users fires the trigger that creates profiles.
insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS is enabled on profiles'
);

select is(
  (select count(*)::int from public.profiles),
  2,
  'sign-up trigger created a profile per user'
);

-- Act as Alice.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.profiles),
  1,
  'Alice sees only her own profile'
);

select is(
  (select id from public.profiles),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'and it is hers'
);

update public.profiles set display_name = 'hacked'
where id = '22222222-2222-2222-2222-222222222222';

select throws_ok(
  $$ insert into public.profiles (id) values ('33333333-3333-3333-3333-333333333333') $$,
  '42501',
  null,
  'Alice cannot insert profiles directly'
);

-- Signed out.
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is(
  (select count(*)::int from public.profiles),
  0,
  'anonymous users see no profiles'
);

reset role;

select is(
  (select display_name from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  null,
  'Alice could not change Bob''s profile'
);

select * from finish();
rollback;
