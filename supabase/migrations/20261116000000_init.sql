-- Israeli MBA Network: database schema and privacy rules (Supabase / Postgres).
--
-- Who can see what:
--   * Nobody who is logged out can read anything.
--   * A pending member (signed up, waiting for approval) sees only their own profile.
--   * Approved members see every approved member's profile, schools and career.
--   * Phone numbers and email addresses live in a separate table (member_contacts) that only
--     the member themselves and admins can read. Phase 3 adds one more reader: someone whose
--     intro request the member accepted.
--   * All writes go through the functions at the bottom of this file, never straight into the
--     tables, so nobody can approve themselves or edit someone else's profile.
--
-- Run it once in the Supabase dashboard: SQL Editor -> New query -> paste this file -> Run.

create extension if not exists citext;

-- ---------------------------------------------------------------- tables

-- One row per member, keyed by their login (Supabase Auth user id).
create table public.members (
  id            uuid primary key references auth.users(id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending','approved','declined')),
  first_name    text not null check (length(trim(first_name)) between 1 and 80),
  last_name     text not null check (length(trim(last_name)) between 1 and 80),
  headline      text not null check (length(trim(headline)) between 1 and 160),
  location      text not null default '',
  industry      text not null default '',
  about         text not null default '' check (length(about) <= 2000),
  contact_pref  text not null default 'email' check (contact_pref in ('whatsapp','email')),
  can_refer     boolean not null default false,
  -- Israeli background (optional)
  unit          text not null default '',
  il_university text not null default '',
  hometown      text not null default '',
  topics        text[] not null default '{}',
  photo_path    text,                       -- file path in the "avatars" storage bucket (phase 2)
  linkedin_url  text not null default '',
  -- Sign-up review
  join_answer   text not null default '' check (length(join_answer) <= 2000),
  signup_source text not null default 'manual' check (signup_source in ('manual','linkedin')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid references auth.users(id),
  -- Set by the email function so each email goes out once
  admin_notified_at timestamptz,
  welcome_sent_at   timestamptz
);
create index members_status_idx on public.members(status);

-- Private: phone and email. Never readable by other members (see policies below).
create table public.member_contacts (
  member_id uuid primary key references public.members(id) on delete cascade,
  email     citext not null,
  phone     text not null default '' check (phone = '' or phone ~ '^\+?[0-9 ().-]{9,25}$')
);

-- One row per normalized company, so "Google" and "Google LLC" land on one company page.
create table public.companies (
  id         bigint generated always as identity primary key,
  name       text not null,
  name_key   text not null unique,          -- normalized form used for matching
  aliases    text[] not null default '{}',  -- other spellings that map here
  created_at timestamptz not null default now()
);

create table public.member_schools (
  id           bigint generated always as identity primary key,
  member_id    uuid not null references public.members(id) on delete cascade,
  school       text not null,               -- key from the app's SCHOOLS list, e.g. 'MIT Sloan'
  program      text not null default 'MBA',
  class_year   int  not null check (class_year between 1970 and 2040),
  start_year   int  check (start_year between 1965 and 2040),
  concentration text not null default '',
  clubs        text[] not null default '{}',
  sort         int  not null default 0
);
create index member_schools_member_idx on public.member_schools(member_id);
create index member_schools_school_idx on public.member_schools(school, class_year);

create table public.career (
  id          bigint generated always as identity primary key,
  member_id   uuid not null references public.members(id) on delete cascade,
  company_id  bigint not null references public.companies(id),
  role        text not null default '',
  start_year  int,
  end_year    int,                          -- null = current role
  location    text not null default '',
  sort        int  not null default 0
);
create index career_member_idx on public.career(member_id);
create index career_company_idx on public.career(company_id);

-- Phase 3: intro requests. Stored now so the privacy rule for contacts can reference them.
create table public.intro_requests (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.members(id) on delete cascade,
  recipient_id  uuid not null references public.members(id) on delete cascade,
  note          text not null check (length(trim(note)) between 1 and 1000),
  status        text not null default 'pending' check (status in ('pending','accepted','declined','withdrawn')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  check (requester_id <> recipient_id)
);
create index intro_requests_recipient_idx on public.intro_requests(recipient_id, status);
create index intro_requests_requester_idx on public.intro_requests(requester_id, status);

-- Admins: add a row here (in the dashboard) for each person who can approve members.
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ---------------------------------------------------------------- helpers

-- These run with the owner's rights so policies can call them without recursion.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.members where id = auth.uid() and status = 'approved');
$$;

-- Can the current user see this member's profile?
create or replace function public.can_see_member(m uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select m = auth.uid()
      or public.is_admin()
      or (public.is_approved() and exists (select 1 from public.members where id = m and status = 'approved'));
$$;

create or replace function public.company_key(n text) returns text
language sql immutable set search_path = '' as $$
  select trim(regexp_replace(
           regexp_replace(lower(coalesce(n,'')), '[.,]|\m(inc|llc|ltd|corp|corporation|co|company|plc|gmbh)\M', ' ', 'g'),
         '\s+', ' ', 'g'));
$$;

-- Find a company by name or alias, creating it if it's new. Returns its id.
create or replace function public.company_id_for(n text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare k text := public.company_key(n); cid bigint;
begin
  if k = '' then return null; end if;
  select id into cid from public.companies where name_key = k or k = any(aliases) limit 1;
  if cid is null then
    insert into public.companies(name, name_key) values (trim(n), k)
    on conflict (name_key) do update set name = public.companies.name
    returning id into cid;
  end if;
  return cid;
end $$;

-- ---------------------------------------------------------------- privacy rules (row level security)

alter table public.members         enable row level security;
alter table public.member_contacts enable row level security;
alter table public.companies       enable row level security;
alter table public.member_schools  enable row level security;
alter table public.career          enable row level security;
alter table public.intro_requests  enable row level security;
alter table public.admins          enable row level security;

-- Reads only. With no insert/update/delete policies, every write must go through the functions below.
create policy "see visible members"   on public.members        for select to authenticated using (public.can_see_member(id));
create policy "see visible schools"   on public.member_schools for select to authenticated using (public.can_see_member(member_id));
create policy "see visible careers"   on public.career         for select to authenticated using (public.can_see_member(member_id));
create policy "members see companies" on public.companies      for select to authenticated using (public.is_approved() or public.is_admin());

-- Contacts: yourself, admins, or someone whose intro you accepted.
create policy "see allowed contacts" on public.member_contacts for select to authenticated using (
  member_id = auth.uid()
  or public.is_admin()
  or exists (select 1 from public.intro_requests r
             where r.recipient_id = member_contacts.member_id
               and r.requester_id = auth.uid()
               and r.status = 'accepted')
);

create policy "see own intros" on public.intro_requests for select to authenticated
  using (requester_id = auth.uid() or recipient_id = auth.uid());

create policy "see own admin row" on public.admins for select to authenticated using (user_id = auth.uid());

-- Logged-out visitors get nothing, not even the table shapes through the API.
revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;

-- ---------------------------------------------------------------- write functions (phase 1)

-- Submit (or re-submit, while pending) a request to join. The caller must be logged in, which
-- proves they own the email address. Expects:
--   { first, last, headline, location, industry, about, phone, linkedin, source, answer,
--     school, classYear, startYear, program, career: [{company, role, years, location}] }
create or replace function public.submit_join_request(p jsonb) returns public.members
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  em  text := auth.jwt() ->> 'email';
  cur public.members;
  c   jsonb;
  i   int := 0;
  y1 int; y2 int;
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  select * into cur from public.members where id = uid;
  if found and cur.status <> 'pending' then raise exception 'already-%', cur.status using errcode = 'P0001'; end if;
  if coalesce(trim(p->>'school'),'') = '' or coalesce(p->>'classYear','') !~ '^\d{4}$' then
    raise exception 'missing-school' using errcode = '22023';
  end if;

  insert into public.members as m (id, first_name, last_name, headline, location, industry, about, contact_pref,
                                   linkedin_url, join_answer, signup_source)
  values (uid, trim(p->>'first'), trim(p->>'last'), trim(p->>'headline'), coalesce(p->>'location',''),
          coalesce(p->>'industry',''), coalesce(p->>'about',''),
          case when coalesce(p->>'phone','') <> '' then 'whatsapp' else 'email' end,
          coalesce(p->>'linkedin',''), coalesce(p->>'answer',''),
          case when p->>'source' = 'linkedin' then 'linkedin' else 'manual' end)
  on conflict (id) do update set
    first_name = excluded.first_name, last_name = excluded.last_name, headline = excluded.headline,
    location = excluded.location, industry = excluded.industry, about = excluded.about,
    contact_pref = excluded.contact_pref, linkedin_url = excluded.linkedin_url,
    join_answer = excluded.join_answer, signup_source = excluded.signup_source, updated_at = now();

  insert into public.member_contacts(member_id, email, phone)
  values (uid, em, coalesce(trim(p->>'phone'),''))
  on conflict (member_id) do update set email = excluded.email, phone = excluded.phone;

  delete from public.member_schools where member_id = uid;
  insert into public.member_schools(member_id, school, program, class_year, start_year)
  values (uid, trim(p->>'school'), coalesce(nullif(p->>'program',''),'MBA'), (p->>'classYear')::int,
          nullif(p->>'startYear','')::int);

  delete from public.career where member_id = uid;
  for c in select * from jsonb_array_elements(coalesce(p->'career','[]'::jsonb)) loop
    continue when coalesce(trim(c->>'company'),'') = '';
    -- "2021–2025", "2021-Present"
    y1 := nullif(substring(c->>'years' from '^\s*(\d{4})'),'')::int;
    y2 := nullif(substring(c->>'years' from '(\d{4})\s*$'),'')::int;
    if y2 = y1 and (c->>'years') !~ '\d{4}\D+\d{4}' then y2 := null; end if;
    insert into public.career(member_id, company_id, role, start_year, end_year, location, sort)
    values (uid, public.company_id_for(c->>'company'), coalesce(c->>'role',''), y1, y2, coalesce(c->>'location',''), i);
    i := i + 1;
  end loop;

  select * into cur from public.members where id = uid;
  return cur;
end $$;

-- Admin: approve or decline a pending member.
create or replace function public.admin_decide(member uuid, approve boolean) returns public.members
language plpgsql security definer set search_path = '' as $$
declare cur public.members;
begin
  if not public.is_admin() then raise exception 'not-admin' using errcode = '42501'; end if;
  update public.members
     set status = case when approve then 'approved' else 'declined' end,
         decided_at = now(), decided_by = auth.uid(), updated_at = now()
   where id = member and status = 'pending'
  returning * into cur;
  if not found then raise exception 'not-pending' using errcode = 'P0002'; end if;
  return cur;
end $$;

-- Admin: everything needed to review pending requests, including the applicant's email and phone.
create or replace function public.admin_pending_requests() returns table (
  id uuid, first_name text, last_name text, headline text, location text, industry text, about text,
  linkedin_url text, join_answer text, signup_source text, created_at timestamptz,
  email text, phone text, school text, class_year int, career jsonb
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'not-admin' using errcode = '42501'; end if;
  return query
    select m.id, m.first_name, m.last_name, m.headline, m.location, m.industry, m.about,
           m.linkedin_url, m.join_answer, m.signup_source, m.created_at,
           c.email::text, c.phone, s.school, s.class_year,
           coalesce((select jsonb_agg(jsonb_build_object('company', co.name, 'role', k.role,
                                                         'start', k.start_year, 'end', k.end_year) order by k.sort)
                     from public.career k join public.companies co on co.id = k.company_id
                     where k.member_id = m.id), '[]'::jsonb)
      from public.members m
      join public.member_contacts c on c.member_id = m.id
      left join lateral (select ms.school, ms.class_year from public.member_schools ms
                         where ms.member_id = m.id order by ms.sort limit 1) s on true
     where m.status = 'pending'
     order by m.created_at;
end $$;

-- The logged-in user's own full profile (including their own contacts), or nothing if they
-- haven't submitted a request yet. Used right after login.
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
                           'year', s.class_year, 'start', s.start_year) order by s.sort)
                         from public.member_schools s where s.member_id = m.id), '[]'::jsonb),
    'career', coalesce((select jsonb_agg(jsonb_build_object('company', co.name, 'role', k.role,
                          'start', k.start_year, 'end', k.end_year, 'location', k.location) order by k.sort)
                        from public.career k join public.companies co on co.id = k.company_id
                        where k.member_id = m.id), '[]'::jsonb))
  from public.members m join public.member_contacts c on c.member_id = m.id
  where m.id = auth.uid();
$$;

-- Function permissions: logged-in users only. Internal helpers are not callable from the API.
revoke execute on all functions in schema public from public, anon;
grant execute on function public.submit_join_request(jsonb), public.admin_decide(uuid, boolean),
                          public.admin_pending_requests(), public.my_profile(),
                          public.is_admin(), public.is_approved(), public.can_see_member(uuid)
  to authenticated;
revoke execute on function public.company_id_for(text) from authenticated;
