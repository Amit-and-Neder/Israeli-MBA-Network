-- Privacy tests: tries to read and write what each kind of user must NOT be able to.
-- Run with: supabase/tests/run.sh   (needs a local Postgres; see that script)
\set ON_ERROR_STOP on
\set QUIET on

-- ---------- test helpers
create schema t;
grant usage on schema t to anon, authenticated;
create table t.results (n serial, ok boolean, msg text);
grant insert, select on t.results to anon, authenticated;
grant usage on sequence t.results_n_seq to anon, authenticated;

create function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin insert into t.results(ok, msg) values (coalesce(cond, false), msg); end $$;

-- Runs sql and expects it to fail with an error whose message contains `expect`.
create function t.fails(sql text, expect text, msg text) returns void language plpgsql as $$
begin
  begin execute sql;
  exception when others then
    insert into t.results(ok, msg) values (position(expect in sqlerrm) > 0, msg || ' [got: ' || sqlerrm || ']');
    return;
  end;
  insert into t.results(ok, msg) values (false, msg || ' [no error]');
end $$;
grant execute on all functions in schema t to anon, authenticated;

-- ---------- people
-- a: admin, b and c: approved members, p: pending, d: will be declined, o: logged in but never applied
insert into auth.users values
  ('aaaaaaaa-0000-0000-0000-000000000000','admin@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000000','b@example.com'),
  ('cccccccc-0000-0000-0000-000000000000','c@example.com'),
  ('dddddddd-0000-0000-0000-000000000000','d@example.com'),
  ('eeeeeeee-0000-0000-0000-000000000000','p@example.com'),
  ('ffffffff-0000-0000-0000-000000000000','o@example.com');
insert into public.admins values ('aaaaaaaa-0000-0000-0000-000000000000');

-- Everyone except o submits a join request, as themselves.
\set req '{"first":"X","last":"Y","headline":"PM","school":"MIT Sloan","classYear":"2027","phone":"+1 617 555 0100","answer":"Tel Aviv, 8200","career":[{"company":"Google LLC","role":"PM","years":"2021–Present"},{"company":"Monday.com","role":"Analyst","years":"2018–2021"}]}'
begin; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-000000000000","email":"admin@example.com"}',true); set local role authenticated;
select public.submit_join_request(:'req'::jsonb); commit;
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select public.submit_join_request(:'req'::jsonb); commit;
begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select public.submit_join_request(jsonb_set(:'req'::jsonb,'{career,0,company}','"Google"')); commit;
begin; select set_config('request.jwt.claims','{"sub":"dddddddd-0000-0000-0000-000000000000","email":"d@example.com"}',true); set local role authenticated;
select public.submit_join_request(:'req'::jsonb); commit;
begin; select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-0000-0000-000000000000","email":"p@example.com"}',true); set local role authenticated;
-- p tries to sneak a status into the payload
select public.submit_join_request(:'req'::jsonb || '{"status":"approved"}'); commit;

-- ---------- logged out (anon)
begin; set local role anon;
select t.fails('select count(*) from public.members', 'permission denied', 'anon cannot read members');
select t.fails('select count(*) from public.member_contacts', 'permission denied', 'anon cannot read contacts');
select t.fails('select public.my_profile()', 'permission denied', 'anon cannot call my_profile');
select t.fails('select public.submit_join_request(''{}'')', 'permission denied', 'anon cannot submit a join request');
commit;

-- ---------- pending member p, before any approvals
begin; select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-0000-0000-000000000000","email":"p@example.com"}',true); set local role authenticated;
select t.ok((select status from public.members where id = auth.uid()) = 'pending', 'status in the payload is ignored: p is still pending');
select t.ok((select count(*) from public.members) = 1, 'pending member sees only their own profile');
select t.ok((select count(*) from public.member_contacts) = 1, 'pending member sees only their own contacts');
select t.ok((select count(*) from public.companies) = 0, 'pending member cannot browse companies');
select t.ok((select public.my_profile() ->> 'email') = 'p@example.com', 'my_profile returns own email');
commit;

-- ---------- admin approves a, b, c and declines d
begin; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-000000000000","email":"admin@example.com"}',true); set local role authenticated;
select t.ok((select count(*) from public.admin_pending_requests()) = 5, 'admin sees all 5 pending requests');
select t.ok((select email from public.admin_pending_requests() where id = 'eeeeeeee-0000-0000-0000-000000000000') = 'p@example.com', 'admin sees applicant email');
select t.ok((select jsonb_array_length(career) from public.admin_pending_requests() where id = 'bbbbbbbb-0000-0000-0000-000000000000') = 2, 'admin sees applicant career');
select public.admin_decide('aaaaaaaa-0000-0000-0000-000000000000', true);
select public.admin_decide('bbbbbbbb-0000-0000-0000-000000000000', true);
select public.admin_decide('cccccccc-0000-0000-0000-000000000000', true);
select public.admin_decide('dddddddd-0000-0000-0000-000000000000', false);
select t.fails('select public.admin_decide(''bbbbbbbb-0000-0000-0000-000000000000'', false)', 'not-pending', 'a decision cannot be reversed by deciding again');
commit;

-- ---------- approved member b
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok((select count(*) from public.members) = 3, 'approved member sees the 3 approved members only');
select t.ok(not exists (select 1 from public.members where status <> 'approved'), 'approved member sees no pending or declined members');
select t.ok((select count(*) from public.career where member_id = 'cccccccc-0000-0000-0000-000000000000') = 2, 'approved member sees another member''s career');
select t.ok(not exists (select 1 from public.career where member_id = 'eeeeeeee-0000-0000-0000-000000000000'), 'approved member cannot see a pending member''s career');
select t.ok((select count(*) from public.member_contacts) = 1, 'approved member sees only their own contacts');
select t.ok(not exists (select 1 from public.member_contacts where member_id = 'cccccccc-0000-0000-0000-000000000000'), 'approved member cannot read c''s phone or email');
select t.ok((select count(*) from public.companies) = 2, '"Google" and "Google LLC" are one company (2 companies total)');
select t.fails('update public.members set status = ''approved'' where id = ''eeeeeeee-0000-0000-0000-000000000000''', 'permission denied', 'member cannot approve someone by editing the table');
select t.fails('update public.members set headline = ''hacked'' where id = ''cccccccc-0000-0000-0000-000000000000''', 'permission denied', 'member cannot edit someone else''s profile');
select t.fails('insert into public.admins values (auth.uid())', 'permission denied', 'member cannot make themselves admin');
select t.fails('insert into public.intro_requests(requester_id, recipient_id, note, status) values (auth.uid(), ''cccccccc-0000-0000-0000-000000000000'', ''hi'', ''accepted'')', 'permission denied', 'member cannot fake an accepted intro');
select t.fails('select public.admin_decide(''eeeeeeee-0000-0000-0000-000000000000'', true)', 'not-admin', 'member cannot call admin_decide');
select t.fails('select * from public.admin_pending_requests()', 'not-admin', 'member cannot list pending requests');
select t.fails('select public.company_id_for(''Evil Corp'')', 'permission denied', 'member cannot create companies directly');
select t.fails('select public.submit_join_request(''{"first":"X","last":"Y","headline":"Z","school":"MIT Sloan","classYear":"2027"}'')', 'already-approved', 'approved member cannot re-submit to reset their status');
select t.ok((select public.my_profile() ->> 'isAdmin')::boolean = false, 'my_profile says b is not an admin');
commit;

-- ---------- declined member d and never-applied o
begin; select set_config('request.jwt.claims','{"sub":"dddddddd-0000-0000-0000-000000000000","email":"d@example.com"}',true); set local role authenticated;
select t.ok((select count(*) from public.members) = 1, 'declined member sees only themselves');
select t.fails('select public.submit_join_request(''{"first":"X","last":"Y","headline":"Z","school":"MIT Sloan","classYear":"2027"}'')', 'already-declined', 'declined member cannot re-apply to become pending again');
commit;
begin; select set_config('request.jwt.claims','{"sub":"ffffffff-0000-0000-0000-000000000000","email":"o@example.com"}',true); set local role authenticated;
select t.ok((select count(*) from public.members) = 0, 'logged-in non-member sees no members');
select t.ok(public.my_profile() is null, 'logged-in non-member has no profile');
commit;

-- ---------- intros unlock contacts (phase 3 rule, tested now)
insert into public.intro_requests(requester_id, recipient_id, note, status) values
  ('bbbbbbbb-0000-0000-0000-000000000000','cccccccc-0000-0000-0000-000000000000','hi','accepted'),
  ('cccccccc-0000-0000-0000-000000000000','aaaaaaaa-0000-0000-0000-000000000000','hi','pending');
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok((select phone from public.member_contacts where member_id = 'cccccccc-0000-0000-0000-000000000000') = '+1 617 555 0100', 'after c accepts b''s intro, b can read c''s phone');
commit;
begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select t.ok(not exists (select 1 from public.member_contacts where member_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 'accepting does not unlock the requester''s contacts for the recipient');
select t.ok(not exists (select 1 from public.member_contacts where member_id = 'aaaaaaaa-0000-0000-0000-000000000000'), 'a pending intro unlocks nothing');
select t.ok((select count(*) from public.intro_requests) = 2, 'c sees the intros they are part of');
commit;
begin; select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-0000-0000-000000000000","email":"p@example.com"}',true); set local role authenticated;
select t.ok((select count(*) from public.intro_requests) = 0, 'outsiders cannot see other people''s intros');
commit;

-- Results are in t.results; run.sh prints them.
