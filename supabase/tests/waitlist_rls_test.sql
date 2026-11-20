-- pgTAP tests for the waitlist: insert-only for anon and signed-in users.
begin;
select plan(8);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.waitlist'::regclass),
  'RLS is enabled on waitlist'
);

insert into public.waitlist (email, consent_version)
values ('existing@example.test', '2026-11-20');

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select lives_ok(
  $$ insert into public.waitlist (email, platform, dexa, consent_version)
     values ('new@example.test', 'ios', 'bodyspec', '2026-11-20') $$,
  'anon can join the waitlist'
);

select lives_ok(
  $$ insert into public.waitlist (email, consent_version)
     values ('existing@example.test', '2026-11-20')
     on conflict (email) do nothing $$,
  'a duplicate email is ignored without an error'
);

select throws_ok(
  $$ select count(*) from public.waitlist $$,
  '42501',
  null,
  'anon cannot read the waitlist'
);

select throws_ok(
  $$ update public.waitlist set email = 'x@example.test' $$,
  '42501',
  null,
  'anon cannot change waitlist rows'
);

select throws_ok(
  $$ insert into public.waitlist (email, consent_version) values ('Not An Email', '2026-11-20') $$,
  '23514',
  null,
  'invalid emails are rejected'
);

-- Signed-in users cannot read other people's signups either.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok(
  $$ select count(*) from public.waitlist $$,
  '42501',
  null,
  'signed-in users cannot read the waitlist'
);

reset role;

select is(
  (select count(*)::int from public.waitlist),
  2,
  'only the two distinct signups were stored'
);

select * from finish();
rollback;
