-- Tests for 20261124000000_member_data.sql: directory, profile edits, photos, stars, feed and intros.
-- Runs after privacy_test.sql in the same database (reuses its people and helpers):
--   a admin (approved), b and c approved, d declined, p pending, o logged in but never applied.
--   Already there: intro b -> c accepted, intro c -> a pending.
\set ON_ERROR_STOP on
\set QUIET on
\set A 'aaaaaaaa-0000-0000-0000-000000000000'
\set B 'bbbbbbbb-0000-0000-0000-000000000000'
\set C 'cccccccc-0000-0000-0000-000000000000'
\set D 'dddddddd-0000-0000-0000-000000000000'
\set P 'eeeeeeee-0000-0000-0000-000000000000'
\set O 'ffffffff-0000-0000-0000-000000000000'
\set asA 'select set_config(''request.jwt.claims'',''{"sub":"aaaaaaaa-0000-0000-0000-000000000000","email":"admin@example.com"}'',true); set local role authenticated;'
\set asB 'select set_config(''request.jwt.claims'',''{"sub":"bbbbbbbb-0000-0000-0000-000000000000","email":"b@example.com"}'',true); set local role authenticated;'
\set asC 'select set_config(''request.jwt.claims'',''{"sub":"cccccccc-0000-0000-0000-000000000000","email":"c@example.com"}'',true); set local role authenticated;'
\set asD 'select set_config(''request.jwt.claims'',''{"sub":"dddddddd-0000-0000-0000-000000000000","email":"d@example.com"}'',true); set local role authenticated;'
\set asP 'select set_config(''request.jwt.claims'',''{"sub":"eeeeeeee-0000-0000-0000-000000000000","email":"p@example.com"}'',true); set local role authenticated;'
\set asO 'select set_config(''request.jwt.claims'',''{"sub":"ffffffff-0000-0000-0000-000000000000","email":"o@example.com"}'',true); set local role authenticated;'

-- ---------- logged out
begin; set local role anon;
select t.fails('select public.directory()', 'permission denied', 'anon cannot read the directory');
select t.fails('select count(*) from public.posts', 'permission denied', 'anon cannot read posts');
select t.fails('select count(*) from public.stars', 'permission denied', 'anon cannot read stars');
select t.fails('select count(*) from storage.objects', 'permission denied', 'anon cannot list photos');
select t.fails('select public.send_intro(''cccccccc-0000-0000-0000-000000000000'', ''hi'')', 'permission denied', 'anon cannot send intros');
commit;

-- ---------- directory
begin; :asB
select t.ok(jsonb_array_length(public.directory()) = 3, 'approved member: directory lists the 3 approved members');
select t.ok(not exists (select 1 from jsonb_array_elements(public.directory()) x where x->>'id' in (:'P', :'D')), 'directory never lists pending or declined members');
select t.ok(not (public.directory() -> 0 ? 'email') and not (public.directory() -> 0 ? 'phone'), 'directory has no email or phone');
select t.ok(jsonb_array_length((select x->'career' from jsonb_array_elements(public.directory()) x where x->>'id' = :'C')) = 2, 'directory includes career');
commit;
begin; :asP
select t.ok(public.directory() = '[]'::jsonb, 'pending member: directory is empty');
commit;
begin; :asO
select t.ok(public.directory() = '[]'::jsonb, 'logged-in non-member: directory is empty');
commit;
begin; :asA
select t.ok(jsonb_array_length(public.directory()) = 3, 'admin: directory lists approved members');
commit;

-- ---------- editing your own profile
begin; :asB
select public.update_my_profile('{"headline":"Senior PM","topics":["Fintech","PM interviews"],"canRefer":true,"ilUni":"Technion","status":"declined",
  "phone":"+1 212 555 0199","schools":[{"school":"MIT Sloan","program":"MBA","year":2027,"start":2025,"concentration":"Finance","clubs":["Israeli Business Club"]}],
  "career":[{"company":"google llc","role":"PM","start":2021,"end":null},{"company":"Wix","role":"Analyst","years":"2017–2020"}]}'::jsonb);
select t.ok((public.my_profile() ->> 'headline') = 'Senior PM', 'member can change their headline');
select t.ok((public.my_profile() ->> 'status') = 'approved', 'a "status" key in the edit is ignored');
select t.ok((public.my_profile() -> 'topics') = '["Fintech","PM interviews"]'::jsonb, 'topics are saved');
select t.ok((public.my_profile() -> 'schools' -> 0 ->> 'concentration') = 'Finance', 'concentration is saved');
select t.ok((public.my_profile() ->> 'phone') = '+1 212 555 0199', 'phone is saved');
select t.ok((public.my_profile() -> 'career' -> 0 ->> 'end') is null and (public.my_profile() -> 'career' -> 1 ->> 'end') = '2020', 'career years are saved (current role has no end)');
select t.ok((select count(*) from public.companies where name_key like 'google%') = 1, '"google llc" lands on the existing Google company');
select t.ok((public.my_profile() ->> 'last') = 'Y', 'keys left out of the edit stay as they were');
select t.fails('select public.update_my_profile(''{"headline":"' || repeat('x',161) || '"}'')', 'check constraint', 'a 161-character headline is refused');
select t.fails('select public.update_my_profile(''{"schools":[]}'')', 'missing-school', 'cannot remove every school');
select t.fails('select public.update_my_profile(''{"photoPath":"cccccccc-0000-0000-0000-000000000000/x.jpg"}'')', 'bad-photo', 'cannot point your photo at someone else''s file');
select public.update_my_profile('{"photoPath":"bbbbbbbb-0000-0000-0000-000000000000/avatar.jpg"}'::jsonb);
select t.ok((public.my_profile() ->> 'photoPath') = 'bbbbbbbb-0000-0000-0000-000000000000/avatar.jpg', 'member can set a photo in their own folder');
select public.update_my_profile('{"photoPath":""}'::jsonb);
select t.ok((public.my_profile() ->> 'photoPath') is null, 'member can remove their photo');
select public.update_my_profile('{"photoPath":"bbbbbbbb-0000-0000-0000-000000000000/avatar.jpg"}'::jsonb);
commit;
begin; :asP
select public.update_my_profile('{"headline":"Incoming MBA"}'::jsonb);
select t.ok((public.my_profile() ->> 'headline') = 'Incoming MBA' and (public.my_profile() ->> 'status') = 'pending', 'pending member can fix their profile and stays pending');
commit;
begin; :asD
select t.fails('select public.update_my_profile(''{"headline":"Again"}'')', 'already-declined', 'declined member cannot edit');
commit;
begin; :asO
select t.fails('select public.update_my_profile(''{"headline":"Hi"}'')', 'no-profile', 'non-member cannot create a profile by editing');
commit;

-- ---------- photos
begin; :asB
insert into storage.objects(bucket_id, name) values ('avatars', :'B' || '/avatar.jpg');
select t.ok(true, 'member can upload a photo to their own folder');
select t.fails('insert into storage.objects(bucket_id, name) values (''avatars'', ''cccccccc-0000-0000-0000-000000000000/avatar.jpg'')', 'row-level security', 'member cannot upload into someone else''s folder');
insert into storage.objects(bucket_id, name) values ('post-photos', :'B' || '/team.jpg');
select t.ok(true, 'approved member can upload a post photo');
commit;
begin; :asP
insert into storage.objects(bucket_id, name) values ('avatars', :'P' || '/avatar.jpg');
select t.ok(true, 'pending member can upload their own profile photo');
select t.fails('insert into storage.objects(bucket_id, name) values (''post-photos'', ''eeeeeeee-0000-0000-0000-000000000000/x.jpg'')', 'row-level security', 'pending member cannot upload post photos');
select t.ok((select count(*) from storage.objects) = 1, 'pending member sees only their own photo');
commit;
begin; :asC
select t.ok(exists (select 1 from storage.objects where name = :'B' || '/avatar.jpg'), 'approved member sees an approved member''s photo');
select t.ok(not exists (select 1 from storage.objects where name like :'P' || '/%'), 'approved member cannot see a pending member''s photo');
commit;
begin; :asC
delete from storage.objects where name = :'B' || '/avatar.jpg';
commit;
select t.ok(exists (select 1 from storage.objects where name = :'B' || '/avatar.jpg'), 'member cannot delete someone else''s photo');
begin; :asA
select t.ok(exists (select 1 from storage.objects where name = :'P' || '/avatar.jpg'), 'admin sees a pending member''s photo (to review them)');
commit;

-- ---------- stars
begin; :asB
insert into public.stars(member_id) values (:'C');
select t.ok((select count(*) from public.stars) = 1, 'member can star another member');
select t.fails('insert into public.stars(member_id) values (''eeeeeeee-0000-0000-0000-000000000000'')', 'row-level security', 'cannot star a pending member');
select t.fails('insert into public.stars(member_id) values (''bbbbbbbb-0000-0000-0000-000000000000'')', 'check constraint', 'cannot star yourself');
select t.fails('insert into public.stars(owner_id, member_id) values (''cccccccc-0000-0000-0000-000000000000'', ''aaaaaaaa-0000-0000-0000-000000000000'')', 'permission denied', 'cannot add stars for someone else');
commit;
begin; :asC
select t.ok((select count(*) from public.stars) = 0, 'stars are private: c cannot see that b starred them');
delete from public.stars where owner_id = :'B';
commit;
select t.ok((select count(*) from public.stars where owner_id = :'B') = 1, 'nobody can remove someone else''s stars');
begin; :asP
select t.fails('insert into public.stars(member_id) values (''cccccccc-0000-0000-0000-000000000000'')', 'row-level security', 'pending member cannot star');
commit;
begin; :asB
delete from public.stars where member_id = :'C';
select t.ok((select count(*) from public.stars) = 0, 'member can unstar');
commit;

-- ---------- feed
begin; :asB
insert into public.posts(type, body, photo_path) values ('hiring', 'Ramp is hiring PMs in NYC', :'B' || '/team.jpg');
insert into public.posts(type, body) values ('event', 'Hanukkah party in Boston, Dec 6');
select t.ok((select count(*) from public.posts) = 2, 'approved member can post');
select t.fails('insert into public.posts(type, body) values (''job'', ''' || repeat('x',281) || ''')', 'check constraint', 'a 281-character post is refused');
select t.fails('insert into public.posts(type, body, photo_path) values (''job'', ''Open to work'', ''bbbbbbbb-0000-0000-0000-000000000000/x.jpg'')', 'check constraint', 'looking-for-a-job posts cannot have photos');
select t.fails('insert into public.posts(type, body, photo_path) values (''hiring'', ''x'', ''cccccccc-0000-0000-0000-000000000000/x.jpg'')', 'row-level security', 'cannot attach someone else''s photo');
select t.fails('insert into public.posts(author_id, type, body) values (''cccccccc-0000-0000-0000-000000000000'', ''job'', ''as c'')', 'permission denied', 'cannot post as someone else');
select t.fails('insert into public.posts(type, body, created_at) values (''job'', ''old'', ''2020-01-01'')', 'permission denied', 'cannot backdate a post');
commit;
begin; :asC
select t.ok((select count(*) from public.posts) = 2, 'approved member sees others'' posts');
delete from public.posts;
insert into public.post_interest(post_id) select id from public.posts where type = 'event';
select t.ok((select count(*) from public.post_interest) = 1, 'member can mark interest in an event');
select t.fails('insert into public.post_interest(post_id) select id from public.posts where type = ''hiring''', 'row-level security', 'interest only applies to events');
commit;
select t.ok((select count(*) from public.posts where author_id = :'B') = 2, 'members cannot delete someone else''s posts');
begin; :asB
select t.ok((select count(*) from public.post_interest) = 0, 'b cannot see who marked interest (private)');
commit;
begin; :asP
select t.ok((select count(*) from public.posts) = 0, 'pending member sees no posts');
select t.fails('insert into public.posts(type, body) values (''job'', ''hi'')', 'row-level security', 'pending member cannot post');
commit;
begin; :asA
delete from public.posts where type = 'hiring';
select t.ok((select count(*) from public.posts) = 1, 'admin can remove a post');
commit;
begin; :asB
insert into public.posts(type, body) select 'job', 'post ' || g from generate_series(1, 9) g;
select t.ok((select count(*) from public.posts where author_id = auth.uid()) = 10, 'member can post up to 10 times in 24 hours');
select t.fails('insert into public.posts(type, body) values (''job'', ''one too many'')', 'row-level security', 'the 11th post in 24 hours is refused');
commit;

-- ---------- intros
begin; :asB
select t.fails('select public.send_intro(''aaaaaaaa-0000-0000-0000-000000000000'', '''')', 'check constraint', 'an empty note is refused');
select t.ok((public.send_intro(:'A', 'Hi, fellow Sloanie')).status = 'pending', 'member can send an intro');
select t.fails('select public.send_intro(''aaaaaaaa-0000-0000-0000-000000000000'', ''again'')', 'already-open', 'only one open intro per pair');
select t.fails('select public.send_intro(''cccccccc-0000-0000-0000-000000000000'', ''hi'')', 'already-open', 'no new intro once one was accepted');
select t.fails('select public.send_intro(''eeeeeeee-0000-0000-0000-000000000000'', ''hi'')', 'not-member', 'cannot send an intro to a pending member');
select t.fails('select public.send_intro(auth.uid(), ''hi'')', 'self', 'cannot send an intro to yourself');
select t.ok(not exists (select 1 from public.member_contacts where member_id = :'A'), 'a pending intro unlocks nothing');
commit;
begin; :asP
select t.fails('select public.send_intro(''cccccccc-0000-0000-0000-000000000000'', ''hi'')', 'not-approved', 'pending member cannot send intros');
commit;
begin; :asC
select t.fails('select public.respond_intro((select id from public.intro_requests where requester_id = ''bbbbbbbb-0000-0000-0000-000000000000'' and recipient_id = ''aaaaaaaa-0000-0000-0000-000000000000''), true)', 'not-pending', 'only the recipient can answer an intro');
commit;
begin; :asA
select t.ok((public.respond_intro((select id from public.intro_requests where requester_id = :'B' and recipient_id = :'A'), true)).status = 'accepted', 'recipient can accept an intro');
-- (One-way unlocking for regular members is covered in privacy_test.sql; a is an admin and sees every contact.)
commit;
begin; :asB
select t.ok(exists (select 1 from public.member_contacts where member_id = :'A'), 'after a accepts, b can read a''s phone and email');
commit;
begin; :asC
select t.ok((public.withdraw_intro((select id from public.intro_requests where requester_id = :'C' and recipient_id = :'A'))).status = 'withdrawn', 'requester can withdraw a pending intro');
commit;
begin; :asA
select t.fails('select public.respond_intro((select id from public.intro_requests where requester_id = ''cccccccc-0000-0000-0000-000000000000'' and recipient_id = ''aaaaaaaa-0000-0000-0000-000000000000''), true)', 'not-pending', 'a withdrawn intro cannot be accepted');
commit;
insert into public.intro_requests(requester_id, recipient_id, note, status)
  select :'C', :'A', 'old', 'declined' from generate_series(1, 9);
begin; :asC
select t.fails('select public.send_intro(''aaaaaaaa-0000-0000-0000-000000000000'', ''hi again'')', 'rate-limit', 'the 11th intro request in 24 hours is refused');
commit;

-- ---------- deleting your own account (20261125000000_accounts.sql)
begin; set local role anon;
select t.fails('select public.delete_my_account()', 'permission denied', 'anon cannot delete accounts');
commit;
begin; :asB
insert into public.stars(member_id) values (:'C');
commit;
begin; :asC
insert into public.stars(member_id) values (:'B');
commit;
-- a (admin) decided on b; deleting a must not touch b's approval
begin; :asA
select public.delete_my_account();
commit;
select t.ok(not exists (select 1 from auth.users where id = :'A'), 'member can delete their own login');
select t.ok(not exists (select 1 from public.members where id = :'A') and not exists (select 1 from public.admins where user_id = :'A')
  and not exists (select 1 from public.intro_requests where :'A' in (requester_id, recipient_id)), 'their profile, admin rights and intros go with it');
select t.ok((select status from public.members where id = :'B') = 'approved' and (select decided_by from public.members where id = :'B') is null,
  'members they approved stay approved');
begin; :asB
select public.delete_my_account();
commit;
select t.ok(not exists (select 1 from public.posts where author_id = :'B') and not exists (select 1 from public.stars where :'B' in (owner_id, member_id)),
  'their posts and stars (given and received) go with it');
select t.ok(exists (select 1 from auth.users where id = :'C') and exists (select 1 from public.members where id = :'C'), 'nobody else is affected');

-- ---------- one-time review keys for email approval (20261126000000_email_approval.sql)
insert into auth.users values ('99999999-0000-0000-0000-000000000000','q@example.com');
begin; select set_config('request.jwt.claims','{"sub":"99999999-0000-0000-0000-000000000000","email":"q@example.com"}',true); set local role authenticated;
select public.submit_join_request('{"first":"Q","last":"R","headline":"PM","school":"MIT Sloan","classYear":"2027"}'::jsonb);
select t.fails('select count(*) from public.review_tokens', 'permission denied', 'members cannot read review keys');
select public.submit_join_request('{"first":"Q","last":"Rr","headline":"PM","school":"MIT Sloan","classYear":"2027"}'::jsonb);
commit;
begin; set local role anon;
select t.fails('select count(*) from public.review_tokens', 'permission denied', 'anon cannot read review keys');
commit;
select t.ok((select count(*) from public.review_tokens where member_id = '99999999-0000-0000-0000-000000000000') = 1
  and (select length(token) from public.review_tokens where member_id = '99999999-0000-0000-0000-000000000000') = 64,
  'a new pending request gets one 64-character review key (re-submitting keeps it)');
select t.ok(not exists (select 1 from public.review_tokens r join public.members m on m.id = r.member_id where m.status <> 'pending'),
  'approved and declined members have no review key');
update public.members set status = 'approved' where id = '99999999-0000-0000-0000-000000000000';
select t.ok(not exists (select 1 from public.review_tokens where member_id = '99999999-0000-0000-0000-000000000000'),
  'deciding a request deletes its key, so the emailed buttons stop working');

-- ---------- email already in use (20261127000000_email_check.sql)
begin; set local role anon;
select t.ok(public.email_in_use('c@example.com'), 'sign-up form: a registered email is reported as taken');
select t.ok(public.email_in_use('  C@Example.COM '), 'the check ignores capital letters and spaces');
select t.ok(not public.email_in_use('nobody@example.com'), 'an unused email is reported as free');
select t.fails('select count(*) from auth.users', 'permission denied', 'the check does not open the login table');
commit;
