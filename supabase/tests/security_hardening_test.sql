-- Security hardening tests (20261203000000_security_hardening.sql). Runs after privacy_test.sql:
-- a is the admin, b and c are approved members.
\set ON_ERROR_STOP on
\set QUIET on

-- 1. private member columns
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok((select first_name from public.members where id = 'cccccccc-0000-0000-0000-000000000000') is not null, 'members still read other members'' public columns');
select t.fails('select join_answer from public.members limit 1', 'permission denied', 'members cannot read sign-up answers');
select t.fails('select decided_by from public.members limit 1', 'permission denied', 'members cannot read who approved someone');
select t.fails('select signup_source from public.members limit 1', 'permission denied', 'members cannot read the sign-up source');
select t.ok(jsonb_array_length(public.directory()) > 0, 'the directory still works');
commit;
begin; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-000000000000","email":"admin@example.com"}',true); set local role authenticated;
select t.ok((select count(*) from public.admin_pending_requests()) >= 0, 'admins still get join requests (with answers) through the admin function');
commit;

-- 2. size limits
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.fails($q$select public.update_my_profile(jsonb_build_object('location', repeat('x', 121)))$q$, 'members_field_sizes', 'a 121-character location is refused');
select t.fails($q$select public.update_my_profile(jsonb_build_object('linkedin', repeat('x', 301)))$q$, 'members_field_sizes', 'a 301-character LinkedIn link is refused');
select t.fails($q$select public.update_my_profile(jsonb_build_object('topics', (select jsonb_agg(i::text) from generate_series(1, 21) i)))$q$, 'members_field_sizes', 'more than 20 topics are refused');
select t.fails($q$select public.update_my_profile(jsonb_build_object('career', jsonb_build_array(jsonb_build_object('company', 'Wix', 'role', repeat('x', 161)))))$q$, 'career_field_sizes', 'a 161-character job title is refused');
select t.fails($q$select public.update_my_profile(jsonb_build_object('career', (select jsonb_agg(jsonb_build_object('company', 'Co ' || i, 'role', 'PM')) from generate_series(1, 41) i)))$q$, 'too-many-rows', 'more than 40 jobs are refused');
select t.fails($q$select public.update_my_profile(jsonb_build_object('schools', (select jsonb_agg(jsonb_build_object('school', 'MIT Sloan', 'year', 2020)) from generate_series(1, 6) i)))$q$, 'too-many-rows', 'more than 5 schools are refused');
select t.fails($q$select public.update_my_profile(jsonb_build_object('career', jsonb_build_array(jsonb_build_object('company', repeat('x', 161), 'role', 'PM'))))$q$, 'companies_name_size', 'a 161-character company name is refused');
select public.update_my_profile(jsonb_build_object('location', repeat('x', 120), 'career', (select jsonb_agg(jsonb_build_object('company', 'Co ' || i, 'role', 'PM')) from generate_series(1, 40) i)));
select t.ok((select count(*) from public.career where member_id = auth.uid()) = 40, 'values at the limit still save (120-character location, 40 jobs)');
commit;

-- 3. the email check is limited per visitor
begin; set local role anon;
select set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7"}', true);
select t.ok(public.email_in_use('c@example.com') and not public.email_in_use('nobody@example.com'), 'logged-out visitors can still check an email');
select public.email_in_use('x' || i || '@example.com') from generate_series(1, 18) i;
select t.fails('select public.email_in_use(''y@example.com'')', 'rate-limit', 'the 21st check in an hour from one visitor is refused');
select set_config('request.headers', '{"cf-connecting-ip":"198.51.100.9"}', true);
select t.ok(not public.email_in_use('z@example.com'), 'another visitor is not affected');
select t.fails('select count(*) from public.email_checks', 'permission denied', 'visitors cannot read the check log');
commit;
