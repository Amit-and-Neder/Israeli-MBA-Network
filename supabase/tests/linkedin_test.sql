-- LinkedIn verification tests (20261205000000_linkedin_verification.sql). Runs after privacy_test.sql.
\set ON_ERROR_STOP on
\set QUIET on

update public.app_settings set value = 'true' where key = 'require_linkedin';

-- Name matching
select t.ok(public.name_matches_linkedin('Amit', 'Goldig', 'Amit Goldig'), 'exact name matches');
select t.ok(public.name_matches_linkedin('amit', 'GOLDIG', 'Amit Goldig'), 'capital letters do not matter');
select t.ok(public.name_matches_linkedin('Amit', 'Goldig', 'Amit David Goldig'), 'a middle name on LinkedIn is fine');
select t.ok(public.name_matches_linkedin('Noa', 'Cohen', 'Noa Cohen (Levi)'), 'a maiden name in brackets on LinkedIn is fine');
select t.ok(public.name_matches_linkedin('Tal', 'Ben-David', 'Tal Ben David'), 'hyphen vs space is fine');
select t.ok(public.name_matches_linkedin('דנה', 'בן-דוד', 'דנה בן דוד'), 'Hebrew names match');
select t.ok(public.name_matches_linkedin('Sean', 'O''Brien', 'Sean OBrien'), 'apostrophes are ignored');
select t.ok(not public.name_matches_linkedin('Amit', 'Goldig', 'Amit Cohen'), 'a different last name does not match');
select t.ok(not public.name_matches_linkedin('Amit', 'Goldig', 'Amit'), 'first name alone does not match');
select t.ok(not public.name_matches_linkedin('Amit', 'Goldig', ''), 'an empty LinkedIn name does not match');

-- People: l1 has LinkedIn as "Lior Katz"; l2 signs up with someone else's PDF; l3 has no LinkedIn
insert into auth.users values ('11111111-0000-0000-0000-000000000000','l1@example.com'),
                              ('22222222-0000-0000-0000-000000000000','l2@example.com'),
                              ('33333333-0000-0000-0000-000000000000','l3@example.com');
insert into auth.identities(user_id, provider, identity_data) values
  ('11111111-0000-0000-0000-000000000000','linkedin_oidc','{"given_name":"Lior","family_name":"Katz","name":"Lior Katz"}'),
  ('22222222-0000-0000-0000-000000000000','linkedin_oidc','{"given_name":"Eve","family_name":"Mallory","name":"Eve Mallory"}');
\set req '{"first":"Lior","last":"Katz","headline":"PM","school":"MIT Sloan","classYear":"2025"}'

begin; select set_config('request.jwt.claims','{"sub":"11111111-0000-0000-0000-000000000000","email":"l1@example.com"}',true); set local role authenticated;
select public.submit_join_request(:'req'::jsonb);
commit;
select t.ok((select linkedin_verified and linkedin_name = 'Lior Katz' from public.members where id = '11111111-0000-0000-0000-000000000000'),
            'a sign-up whose name matches their LinkedIn is saved and marked verified');

begin; select set_config('request.jwt.claims','{"sub":"22222222-0000-0000-0000-000000000000","email":"l2@example.com"}',true); set local role authenticated;
select t.fails($q$select public.submit_join_request('{"first":"Lior","last":"Katz","headline":"PM","school":"MIT Sloan","classYear":"2025"}'::jsonb)$q$,
               'linkedin-name-mismatch', 'someone using another person''s PDF is refused');
commit;

begin; select set_config('request.jwt.claims','{"sub":"33333333-0000-0000-0000-000000000000","email":"l3@example.com"}',true); set local role authenticated;
select t.fails($q$select public.submit_join_request('{"first":"Ann","last":"Lee","headline":"PM","school":"MIT Sloan","classYear":"2025"}'::jsonb)$q$,
               'linkedin-required', 'a new sign-up without LinkedIn is refused while the rule is on');
commit;

-- A verified member can't rename themselves to someone else
begin; select set_config('request.jwt.claims','{"sub":"11111111-0000-0000-0000-000000000000","email":"l1@example.com"}',true); set local role authenticated;
select t.fails($q$select public.update_my_profile('{"last":"Goldig"}'::jsonb)$q$, 'linkedin-name-mismatch', 'a verified member cannot change to a name that is not theirs');
select public.update_my_profile('{"headline":"Senior PM"}'::jsonb);
select t.ok((select headline from public.members where id = auth.uid()) = 'Senior PM', 'a verified member can still edit other fields');
commit;

-- Existing members without LinkedIn are not locked out of editing
begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select public.update_my_profile('{"headline":"Still editable"}'::jsonb);
select t.ok((select headline from public.members where id = auth.uid()) = 'Still editable', 'members who joined before LinkedIn can still edit');
commit;

-- The switch
update public.app_settings set value = 'false' where key = 'require_linkedin';
begin; select set_config('request.jwt.claims','{"sub":"33333333-0000-0000-0000-000000000000","email":"l3@example.com"}',true); set local role authenticated;
select public.submit_join_request('{"first":"Ann","last":"Lee","headline":"PM","school":"MIT Sloan","classYear":"2025"}'::jsonb);
commit;
select t.ok(exists (select 1 from public.members where id = '33333333-0000-0000-0000-000000000000' and not linkedin_verified),
            'with the switch off, sign-up without LinkedIn works (not marked verified)');

-- Admins see the badge; members can't read the LinkedIn name
begin; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-000000000000","email":"admin@example.com"}',true); set local role authenticated;
select t.ok((select linkedin_verified from public.admin_pending_requests() where id = '11111111-0000-0000-0000-000000000000'), 'admins see who is LinkedIn-verified');
commit;
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.fails('select linkedin_name from public.members limit 1', 'permission denied', 'members cannot read the LinkedIn name');
commit;
begin; set local role anon;
select t.fails('select * from public.app_settings', 'permission denied', 'nobody can read or change the settings through the API');
commit;
