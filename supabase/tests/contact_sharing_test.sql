-- Contact sharing tests (20261128000000_contact_sharing.sql). Runs after privacy_test.sql,
-- reusing its members b and c. c accepts an intro from b, so b may see c's contact details.
\set ON_ERROR_STOP on
\set QUIET on

delete from public.intro_requests where requester_id = 'bbbbbbbb-0000-0000-0000-000000000000' and recipient_id = 'cccccccc-0000-0000-0000-000000000000';
insert into public.intro_requests(requester_id, recipient_id, note, status)
  values ('bbbbbbbb-0000-0000-0000-000000000000','cccccccc-0000-0000-0000-000000000000','hi','accepted');

-- c keeps only WhatsApp
begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select t.fails('select public.update_my_contact(''{"phone":"","shareEmail":false,"pref":"email"}'')', 'share-one', 'a member must share email or WhatsApp');
select t.fails('select public.update_my_contact(''{"phone":"","shareEmail":true,"pref":"whatsapp"}'')', 'pref-not-shared', 'WhatsApp cannot be preferred without a number');
select t.fails('select public.update_my_contact(''{"phone":"+1 617 555 0100","shareEmail":false,"pref":"email"}'')', 'pref-not-shared', 'email cannot be preferred when it is not shared');
select public.update_my_contact('{"phone":"+1 617 555 0100","shareEmail":false,"pref":"whatsapp"}');
select t.ok((select email from public.visible_contacts() where member_id = 'cccccccc-0000-0000-0000-000000000000') = 'c@example.com', 'members still see their own email');
commit;

-- b, whose intro c accepted
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok((select email from public.visible_contacts() where member_id = 'cccccccc-0000-0000-0000-000000000000') = '', 'an email that is not shared stays hidden after the intro');
select t.ok((select phone from public.visible_contacts() where member_id = 'cccccccc-0000-0000-0000-000000000000') = '+1 617 555 0100', 'the shared WhatsApp number shows after the intro');
select t.fails('select email from public.member_contacts', 'permission denied', 'emails cannot be read from the table directly');
select t.ok(not exists (select 1 from public.visible_contacts() where member_id = 'aaaaaaaa-0000-0000-0000-000000000000'), 'no accepted intro, no contact details');
commit;

-- c shares both again
begin; select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}',true); set local role authenticated;
select public.update_my_contact('{"phone":"+1 617 555 0100","shareEmail":true,"pref":"email"}');
select t.ok((select contact_pref from public.members where id = 'cccccccc-0000-0000-0000-000000000000') = 'email', 'the preferred method is saved');
commit;
begin; select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}',true); set local role authenticated;
select t.ok((select email from public.visible_contacts() where member_id = 'cccccccc-0000-0000-0000-000000000000') = 'c@example.com', 'a shared email shows after the intro');
commit;
begin; set local role anon;
select t.fails('select * from public.visible_contacts()', 'permission denied', 'logged-out visitors cannot call visible_contacts');
commit;
