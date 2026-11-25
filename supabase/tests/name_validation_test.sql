-- Name rule tests (20261202000000_name_validation.sql). Runs after privacy_test.sql: b is an approved member.
\set ON_ERROR_STOP on
\set QUIET on

select t.ok(public.valid_person_name(n), 'allowed name: ' || n)
  from unnest(array['Dana', 'Ben-David', 'O''Brien', 'O’Neil', 'J. R.', 'José', 'Zoë', 'דנה', 'בן-דוד', 'ג׳ני', 'Наталья', 'محمد', 'van der Berg']) n;
select t.ok(not public.valid_person_name(n), 'refused name: ' || n)
  from unnest(array['Robert''); drop table members; --', 'x'' or 1=1', 'a;b', 'Dana"', 'Dana`', 'a=b', '<script>', 'Dana1', 'Da--na',
                    '-Dana', '''Dana', ' Dana', 'Dana*', 'a/b', 'a\b', 'a%', 'a@b', '#a', 'a(b)', '']) n;

begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.fails('select public.update_my_profile(''{"first":"Bob; drop table members"}''::jsonb)', 'bad-name', 'a profile save with a bad first name is refused');
select t.fails('select public.update_my_profile(''{"last":"x'''' or 1=1 --"}''::jsonb)', 'bad-name', 'a profile save with a bad last name is refused');
select public.update_my_profile('{"first":"Bea-Lee","last":"O''Hara"}'::jsonb);
select t.ok((select first_name || ' ' || last_name from public.members where id = auth.uid()) = 'Bea-Lee O''Hara', 'a normal name with a hyphen and apostrophe saves');
select public.update_my_profile('{"first":"X","last":"Y"}'::jsonb);
commit;

begin; select set_config('request.jwt.claims','{"sub":"ffffffff-0000-0000-0000-000000000000","email":"f@example.com"}',true); set local role authenticated;
select t.fails($q$select public.submit_join_request('{"first":"<b>Eve</b>","last":"Smith","headline":"PM","school":"MIT Sloan","classYear":"2024"}'::jsonb)$q$, 'bad-name', 'a join request with a bad name is refused');
commit;

-- The email function writes to members with the service_role key (admin_notified_at, welcome_sent_at,
-- status from the emailed Approve button). The name rule must not block it.
do $$ declare n int := 0; e text := ''; begin
  set local role service_role;
  begin
    update public.members set admin_notified_at = admin_notified_at where id = 'bbbbbbbb-0000-0000-0000-000000000000';
    get diagnostics n = row_count;
    update public.members set first_name = first_name where id = 'bbbbbbbb-0000-0000-0000-000000000000';
  exception when others then e := sqlerrm; end;
  reset role;
  perform t.ok(n = 1 and e = '', 'the email function (service_role) can update a member row [' || e || ']');
end $$;
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.fails('select public.valid_person_name(''x'')', 'permission denied', 'members still cannot call the name check directly');
commit;
