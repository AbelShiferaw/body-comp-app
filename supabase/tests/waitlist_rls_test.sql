-- pgTAP tests for the waitlist: write-only through join_waitlist(), no reads.
begin;
select plan(9);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.waitlist'::regclass),
  'RLS is enabled on waitlist'
);

insert into public.waitlist (email, consent_version)
values ('existing@example.test', '2026-11-20');

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select lives_ok(
  $$ select public.join_waitlist('New@Example.test', 'ios', 'bodyspec', '2026-11-20') $$,
  'anon can join the waitlist'
);

select lives_ok(
  $$ select public.join_waitlist('existing@example.test', null, null, '2026-11-20') $$,
  'a duplicate email is ignored without an error'
);

select throws_ok(
  $$ select public.join_waitlist('Not An Email', null, null, '2026-11-20') $$,
  '23514',
  null,
  'invalid emails are rejected'
);

select throws_ok(
  $$ select count(*) from public.waitlist $$,
  '42501',
  null,
  'anon cannot read the waitlist'
);

select throws_ok(
  $$ insert into public.waitlist (email, consent_version) values ('direct@example.test', 'x') $$,
  '42501',
  null,
  'anon cannot insert into the table directly'
);

select throws_ok(
  $$ delete from public.waitlist $$,
  '42501',
  null,
  'anon cannot delete waitlist rows'
);

-- Signed-in app users cannot read other people's signups either.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok(
  $$ select count(*) from public.waitlist $$,
  '42501',
  null,
  'signed-in users cannot read the waitlist'
);

reset role;

select results_eq(
  $$ select email, source from public.waitlist order by email $$,
  $$ values ('existing@example.test'::text, 'website'::text), ('new@example.test', 'website') $$,
  'only the two distinct, normalized signups were stored'
);

select * from finish();
rollback;
