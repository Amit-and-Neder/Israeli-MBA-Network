-- Report tests (20261201000000_reports.sql). Runs after privacy_test.sql:
-- a is the admin, b and c are approved members, p (eeeeeeee) is pending.
\set ON_ERROR_STOP on
\set QUIET on

-- b reports c
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select public.report_member('cccccccc-0000-0000-0000-000000000000', 'spam', '  Keeps posting ads  ');
select t.ok(true, 'an approved member can report another member');
select t.fails('select public.report_member(''bbbbbbbb-0000-0000-0000-000000000000'', ''spam'', '''')', 'self-report', 'members cannot report themselves');
select t.fails('select public.report_member(''cccccccc-0000-0000-0000-000000000000'', ''rude'', '''')', 'bad-reason', 'only the listed reasons are accepted');
select t.fails('select public.report_member(''eeeeeeee-0000-0000-0000-000000000000'', ''fake'', '''')', 'no-member', 'pending applicants cannot be reported (members cannot see them)');
select t.fails('select count(*) from public.reports', 'permission denied', 'members cannot read reports');
select t.fails('select * from public.admin_reports()', 'not-admin', 'members cannot list reports');
commit;

-- c (the reported member) learns nothing
begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select t.fails('select * from public.reports', 'permission denied', 'the reported member cannot see reports about them');
commit;

-- p, pending, cannot report
begin; select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-0000-0000-000000000000","email":"p@example.com"}',true); set local role authenticated;
select t.fails('select public.report_member(''cccccccc-0000-0000-0000-000000000000'', ''spam'', '''')', 'not-approved', 'pending applicants cannot report');
commit;

-- the admin reviews and resolves
begin; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-000000000000","email":"admin@example.com"}',true); set local role authenticated;
select t.ok((select details from public.admin_reports() where reported_id = 'cccccccc-0000-0000-0000-000000000000' limit 1) = 'Keeps posting ads', 'the admin sees the report and its details');
select t.ok((select open_count from public.admin_reports() where reported_id = 'cccccccc-0000-0000-0000-000000000000' limit 1) = 1, 'the admin sees how many open reports a member has');
select public.admin_resolve_report((select id from public.admin_reports() where reported_id = 'cccccccc-0000-0000-0000-000000000000' limit 1));
select t.ok((select status from public.admin_reports() where reported_id = 'cccccccc-0000-0000-0000-000000000000' limit 1) = 'resolved', 'the admin can resolve a report');
commit;

begin; set local role anon;
select t.fails('select public.report_member(''cccccccc-0000-0000-0000-000000000000'', ''spam'', '''')', 'permission denied', 'logged-out visitors cannot report');
commit;
