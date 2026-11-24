-- Status note tests (20261130000000_status_note.sql). Runs after privacy_test.sql:
-- b and c are approved, p (eeeeeeee) is pending.
\set ON_ERROR_STOP on
\set QUIET on

begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select public.set_my_status('  Moving to   NYC in June, happy to grab coffee!  ');
select t.ok((select note from public.status_notes() where member_id = auth.uid()) = 'Moving to NYC in June, happy to grab coffee!', 'a member sets a note; spaces are tidied');
select public.set_my_status(repeat('x', 150));
select t.ok((select length(note) from public.status_notes() where member_id = auth.uid()) = 100, 'notes are cut to 100 characters');
select public.set_my_status('Hiring PMs at Wix');
commit;

begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok((select note from public.status_notes() where member_id = 'cccccccc-0000-0000-0000-000000000000') = 'Hiring PMs at Wix', 'approved members see each other''s notes');
commit;

begin; select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-0000-0000-000000000000","email":"p@example.com"}',true); set local role authenticated;
select public.set_my_status('Just applied!');
select t.ok(not exists (select 1 from public.status_notes() where member_id = 'cccccccc-0000-0000-0000-000000000000'), 'a pending applicant does not see members'' notes');
select t.ok((select note from public.status_notes() where member_id = auth.uid()) = 'Just applied!', 'a pending applicant sees their own note');
commit;

begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok(not exists (select 1 from public.status_notes() where member_id = 'eeeeeeee-0000-0000-0000-000000000000'), 'members do not see a pending applicant''s note');
commit;

begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select public.set_my_status('');
select t.ok(not exists (select 1 from public.status_notes() where member_id = auth.uid()), 'an empty note clears it');
commit;

begin; set local role anon;
select t.fails('select * from public.status_notes()', 'permission denied', 'logged-out visitors cannot read notes');
select t.fails('select public.set_my_status(''hi'')', 'permission denied', 'logged-out visitors cannot set a note');
commit;
