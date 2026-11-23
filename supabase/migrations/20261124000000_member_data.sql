-- Israeli MBA Network: phase 2. Everything members do is saved here, not in the browser:
-- profile edits and photos, stars, feed posts (with photos and "interested"), and intro requests.
--
-- Run once, after 20261116000000_init.sql: Supabase -> SQL Editor -> paste this file -> Run.
-- Safe to run again: every object is created with "or replace" / "if not exists" or dropped first.
--
-- Who can do what (enforced here, not in the page):
--   Logged out:        nothing.
--   Pending member:    read and edit only their own profile and photo.
--   Approved member:   read approved members, their photos, posts and schools; star members; post;
--                      send, accept, decline and withdraw intros. Someone else's phone and email only
--                      after they accepted your intro (rule from 20261116000000_init.sql, unchanged).
--   Admin:             everything an approved member can, plus reading anyone and removing posts.

-- ---------------------------------------------------------------- limits

-- How many posts or intro requests the caller made in the last 24 hours, so one account can't flood the network.
-- (Defined after the posts table below.)

-- ---------------------------------------------------------------- reading the directory

-- Every approved member the caller may see, with schools and career, in one call.
-- Pending and declined members never appear here; contacts are read separately (member_contacts).
create or replace function public.directory() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'first', m.first_name, 'last', m.last_name, 'headline', m.headline,
    'location', m.location, 'industry', m.industry, 'about', m.about, 'pref', m.contact_pref,
    'canRefer', m.can_refer, 'unit', m.unit, 'ilUni', m.il_university, 'hometown', m.hometown,
    'topics', m.topics, 'linkedin', m.linkedin_url, 'photoPath', m.photo_path,
    'schools', coalesce((select jsonb_agg(jsonb_build_object('school', s.school, 'program', s.program,
                           'year', s.class_year, 'start', s.start_year, 'concentration', s.concentration,
                           'clubs', s.clubs) order by s.sort)
                         from public.member_schools s where s.member_id = m.id), '[]'::jsonb),
    'career', coalesce((select jsonb_agg(jsonb_build_object('company', co.name, 'role', k.role,
                          'start', k.start_year, 'end', k.end_year, 'location', k.location) order by k.sort)
                        from public.career k join public.companies co on co.id = k.company_id
                        where k.member_id = m.id), '[]'::jsonb)
  ) order by m.first_name, m.last_name), '[]'::jsonb)
  from public.members m
  where m.status = 'approved' and (public.is_approved() or public.is_admin());
$$;

-- The caller's own profile, now with concentration and clubs (replaces the phase 1 version).
create or replace function public.my_profile() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', m.id, 'status', m.status, 'first', m.first_name, 'last', m.last_name, 'headline', m.headline,
    'location', m.location, 'industry', m.industry, 'about', m.about, 'pref', m.contact_pref,
    'canRefer', m.can_refer, 'unit', m.unit, 'ilUni', m.il_university, 'hometown', m.hometown,
    'topics', m.topics, 'linkedin', m.linkedin_url, 'photoPath', m.photo_path,
    'email', c.email, 'phone', c.phone,
    'isAdmin', public.is_admin(),
    'schools', coalesce((select jsonb_agg(jsonb_build_object('school', s.school, 'program', s.program,
                           'year', s.class_year, 'start', s.start_year, 'concentration', s.concentration,
                           'clubs', s.clubs) order by s.sort)
                         from public.member_schools s where s.member_id = m.id), '[]'::jsonb),
    'career', coalesce((select jsonb_agg(jsonb_build_object('company', co.name, 'role', k.role,
                          'start', k.start_year, 'end', k.end_year, 'location', k.location) order by k.sort)
                        from public.career k join public.companies co on co.id = k.company_id
                        where k.member_id = m.id), '[]'::jsonb))
  from public.members m join public.member_contacts c on c.member_id = m.id
  where m.id = auth.uid();
$$;

-- ---------------------------------------------------------------- editing your own profile

-- Saves the caller's profile. Only keys present in p change; "schools" and "career" replace the whole list.
-- Status, admin rights and who decided are never touched here.
create or replace function public.update_my_profile(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  cur public.members;
  s jsonb; c jsonb; i int; y1 int; y2 int;
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  select * into cur from public.members where id = uid;
  if not found then raise exception 'no-profile' using errcode = 'P0002'; end if;
  if cur.status = 'declined' then raise exception 'already-declined' using errcode = 'P0001'; end if;
  if nullif(p->>'photoPath', '') is not null and position(uid::text || '/' in p->>'photoPath') <> 1 then
    raise exception 'bad-photo' using errcode = '22023';
  end if;

  update public.members set
    first_name    = coalesce(trim(p->>'first'), first_name),
    last_name     = coalesce(trim(p->>'last'), last_name),
    headline      = coalesce(trim(p->>'headline'), headline),
    location      = coalesce(p->>'location', location),
    industry      = coalesce(p->>'industry', industry),
    about         = coalesce(p->>'about', about),
    contact_pref  = case when p ? 'pref' and p->>'pref' in ('whatsapp','email') then p->>'pref' else contact_pref end,
    can_refer     = coalesce((p->>'canRefer')::boolean, can_refer),
    unit          = coalesce(trim(p->>'unit'), unit),
    il_university = coalesce(trim(p->>'ilUni'), il_university),
    hometown      = coalesce(trim(p->>'hometown'), hometown),
    topics        = case when p ? 'topics' then coalesce(array(select jsonb_array_elements_text(p->'topics')), '{}') else topics end,
    linkedin_url  = coalesce(trim(p->>'linkedin'), linkedin_url),
    photo_path    = case when p ? 'photoPath' then nullif(p->>'photoPath', '') else photo_path end,
    updated_at    = now()
  where id = uid;

  if p ? 'phone' then
    update public.member_contacts set phone = coalesce(trim(p->>'phone'), '') where member_id = uid;
  end if;

  if p ? 'schools' then
    if jsonb_array_length(coalesce(p->'schools', '[]'::jsonb)) = 0 then raise exception 'missing-school' using errcode = '22023'; end if;
    delete from public.member_schools where member_id = uid;
    i := 0;
    for s in select * from jsonb_array_elements(p->'schools') loop
      insert into public.member_schools(member_id, school, program, class_year, start_year, concentration, clubs, sort)
      values (uid, trim(s->>'school'), coalesce(nullif(s->>'program',''), 'MBA'), (s->>'year')::int,
              nullif(s->>'start','')::int, coalesce(trim(s->>'concentration'), ''),
              coalesce(array(select jsonb_array_elements_text(s->'clubs')), '{}'), i);
      i := i + 1;
    end loop;
  end if;

  if p ? 'career' then
    delete from public.career where member_id = uid;
    i := 0;
    for c in select * from jsonb_array_elements(coalesce(p->'career', '[]'::jsonb)) loop
      continue when coalesce(trim(c->>'company'), '') = '';
      -- "2021–2025", "2021-Present", or start/end given directly
      y1 := coalesce(nullif(c->>'start','')::int, nullif(substring(c->>'years' from '^\s*(\d{4})'), '')::int);
      y2 := case when c ? 'end' then nullif(c->>'end','')::int
                 else nullif(substring(c->>'years' from '(\d{4})\s*$'), '')::int end;
      if not (c ? 'end') and y2 = y1 and coalesce(c->>'years','') !~ '\d{4}\D+\d{4}' then y2 := null; end if;
      insert into public.career(member_id, company_id, role, start_year, end_year, location, sort)
      values (uid, public.company_id_for(c->>'company'), coalesce(c->>'role', ''), y1, y2, coalesce(c->>'location', ''), i);
      i := i + 1;
    end loop;
  end if;

  return public.my_profile();
end $$;

-- ---------------------------------------------------------------- photos (Supabase Storage)

-- Two private buckets. Files live under "<member id>/...", so a member can only write their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars', 'avatars', false, 2097152, array['image/jpeg','image/png','image/webp']),
  ('post-photos', 'post-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "imn read photos" on storage.objects;
drop policy if exists "imn add own photos" on storage.objects;
drop policy if exists "imn change own photos" on storage.objects;
drop policy if exists "imn delete own photos" on storage.objects;
-- Approved members see approved members' photos; admins see all; anyone logged in sees their own.
create policy "imn read photos" on storage.objects for select to authenticated using (
  bucket_id in ('avatars','post-photos')
  and ((storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or (public.is_approved() and exists (select 1 from public.members
                                         where id::text = (storage.foldername(name))[1] and status = 'approved'))));
-- Profile photos: any member with a profile (pending too). Post photos: approved members only.
create policy "imn add own photos" on storage.objects for insert to authenticated with check (
  (storage.foldername(name))[1] = auth.uid()::text
  and ((bucket_id = 'avatars' and exists (select 1 from public.members where id = auth.uid() and status <> 'declined'))
    or (bucket_id = 'post-photos' and public.is_approved())));
create policy "imn change own photos" on storage.objects for update to authenticated
  using (bucket_id in ('avatars','post-photos') and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id in ('avatars','post-photos') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "imn delete own photos" on storage.objects for delete to authenticated using (
  bucket_id in ('avatars','post-photos') and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------- stars

-- Private bookmarks: only the person who starred can see their stars. Nobody is notified.
create table if not exists public.stars (
  owner_id   uuid not null references public.members(id) on delete cascade,
  member_id  uuid not null references public.members(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, member_id),
  check (owner_id <> member_id)
);
alter table public.stars enable row level security;
alter table public.stars alter column owner_id set default auth.uid();
drop policy if exists "see own stars" on public.stars;
drop policy if exists "star approved members" on public.stars;
drop policy if exists "unstar" on public.stars;
create policy "see own stars" on public.stars for select to authenticated using (owner_id = auth.uid());
create policy "star approved members" on public.stars for insert to authenticated with check (
  owner_id = auth.uid() and public.is_approved()
  and exists (select 1 from public.members where id = member_id and status = 'approved'));
create policy "unstar" on public.stars for delete to authenticated using (owner_id = auth.uid());

-- ---------------------------------------------------------------- feed

create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  author_id  uuid not null default auth.uid() references public.members(id) on delete cascade,
  type       text not null check (type in ('job','hiring','event')),
  body       text not null check (length(trim(body)) between 1 and 280),
  photo_path text,                                   -- in the "post-photos" bucket
  created_at timestamptz not null default now(),
  check (photo_path is null or type in ('hiring','event'))
);
create or replace function public.my_recent_count(kind text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare n int;
begin
  if kind = 'posts' then
    select count(*) into n from public.posts where author_id = auth.uid() and created_at > now() - interval '24 hours';
  elsif kind = 'intros' then
    select count(*) into n from public.intro_requests where requester_id = auth.uid() and created_at > now() - interval '24 hours';
  end if;
  return coalesce(n, 0);
end $$;
create index if not exists posts_created_idx on public.posts(created_at desc);
create index if not exists posts_author_idx on public.posts(author_id, created_at desc);
alter table public.posts enable row level security;

drop policy if exists "read posts" on public.posts;
drop policy if exists "write own posts" on public.posts;
drop policy if exists "delete own posts" on public.posts;
create policy "read posts" on public.posts for select to authenticated using (
  author_id = auth.uid()
  or ((public.is_approved() or public.is_admin())
      and exists (select 1 from public.members where id = author_id and status = 'approved')));
create policy "write own posts" on public.posts for insert to authenticated with check (
  author_id = auth.uid() and public.is_approved()
  and (photo_path is null or position(auth.uid()::text || '/' in photo_path) = 1)
  and public.my_recent_count('posts') < 10);
create policy "delete own posts" on public.posts for delete to authenticated using (
  author_id = auth.uid() or public.is_admin());

-- "I'm interested" on events. Only the member themselves sees their own marks.
create table if not exists public.post_interest (
  post_id    uuid not null references public.posts(id) on delete cascade,
  member_id  uuid not null default auth.uid() references public.members(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, member_id)
);
alter table public.post_interest enable row level security;
drop policy if exists "see own interest" on public.post_interest;
drop policy if exists "mark interest" on public.post_interest;
drop policy if exists "unmark interest" on public.post_interest;
create policy "see own interest" on public.post_interest for select to authenticated using (member_id = auth.uid());
create policy "mark interest" on public.post_interest for insert to authenticated with check (
  member_id = auth.uid() and public.is_approved()
  and exists (select 1 from public.posts where id = post_id and type = 'event'));
create policy "unmark interest" on public.post_interest for delete to authenticated using (member_id = auth.uid());

-- ---------------------------------------------------------------- intros

-- Set by the email function so each intro email goes out once.
alter table public.intro_requests add column if not exists notified_at timestamptz;
alter table public.intro_requests add column if not exists accepted_notified_at timestamptz;

-- Ask an approved member for an intro. One open request per pair; at most 10 new requests a day.
create or replace function public.send_intro(recipient uuid, note text) returns public.intro_requests
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); row public.intro_requests;
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  if not public.is_approved() then raise exception 'not-approved' using errcode = '42501'; end if;
  if recipient = uid then raise exception 'self' using errcode = '22023'; end if;
  if not exists (select 1 from public.members where id = recipient and status = 'approved') then
    raise exception 'not-member' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.intro_requests where status in ('pending','accepted')
             and ((requester_id = uid and recipient_id = recipient) or (requester_id = recipient and recipient_id = uid))) then
    raise exception 'already-open' using errcode = 'P0001';
  end if;
  if public.my_recent_count('intros') >= 10 then raise exception 'rate-limit' using errcode = 'P0001'; end if;
  insert into public.intro_requests(requester_id, recipient_id, note) values (uid, recipient, trim(note))
  returning * into row;
  return row;
end $$;

-- The recipient accepts or declines. Accepting lets the requester see the recipient's phone and email.
create or replace function public.respond_intro(intro uuid, accept boolean) returns public.intro_requests
language plpgsql security definer set search_path = '' as $$
declare row public.intro_requests;
begin
  update public.intro_requests set status = case when accept then 'accepted' else 'declined' end, responded_at = now()
   where id = intro and recipient_id = auth.uid() and status = 'pending'
  returning * into row;
  if not found then raise exception 'not-pending' using errcode = 'P0002'; end if;
  return row;
end $$;

-- The requester takes back a request that hasn't been answered yet.
create or replace function public.withdraw_intro(intro uuid) returns public.intro_requests
language plpgsql security definer set search_path = '' as $$
declare row public.intro_requests;
begin
  update public.intro_requests set status = 'withdrawn', responded_at = now()
   where id = intro and requester_id = auth.uid() and status = 'pending'
  returning * into row;
  if not found then raise exception 'not-pending' using errcode = 'P0002'; end if;
  return row;
end $$;

-- ---------------------------------------------------------------- table and function access

-- Supabase may grant new tables to everyone by default; set access explicitly. Policies above pick the rows.
-- Inserts name only the columns a member may set; ids, owners and times come from defaults.
revoke all on public.stars, public.posts, public.post_interest from anon, authenticated;
grant select, delete on public.stars, public.posts, public.post_interest to authenticated;
grant insert (member_id) on public.stars to authenticated;
grant insert (type, body, photo_path) on public.posts to authenticated;
grant insert (post_id) on public.post_interest to authenticated;
grant all on public.stars, public.posts, public.post_interest to service_role;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.directory(), public.update_my_profile(jsonb),
                          public.send_intro(uuid, text), public.respond_intro(uuid, boolean),
                          public.withdraw_intro(uuid), public.my_recent_count(text)
  to authenticated;
