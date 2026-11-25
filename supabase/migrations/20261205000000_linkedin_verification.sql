-- Ba-mba: new members prove who they are with "Sign in with LinkedIn".
--
-- The LinkedIn PDF can be downloaded for anyone's profile and edited, so on its own it proves nothing.
-- New sign-ups therefore log in with their own LinkedIn account (Supabase provider "linkedin_oidc"), and the
-- database checks that the name they submit matches the name on that LinkedIn account. Someone holding
-- another person's PDF can't pass, because they can't log in to that person's LinkedIn.
--
-- Rules (trigger members_linkedin_check, on the member's own sign-up and own name changes):
--   * The caller has a LinkedIn login: every word of the submitted first + last name must appear in the
--     LinkedIn name (letters only, any order, so middle names and "(maiden name)" on LinkedIn are fine).
--     If not: error "linkedin-name-mismatch". If yes: linkedin_verified = true and linkedin_name is kept.
--   * No LinkedIn login: a new sign-up is refused ("linkedin-required") while require_linkedin is on.
--     Existing members without LinkedIn can still edit their profile.
--   * Writes by admins' tools, the email function or the SQL editor (no logged-in user) are not checked.
-- Switch: update public.app_settings set value = 'false' where key = 'require_linkedin';  (e.g. LinkedIn outage)
--
-- Run once, AFTER LinkedIn is turned on in Supabase (Authentication -> Sign In / Providers -> LinkedIn (OIDC))
-- and the site's "Verify with LinkedIn" step is live. Run after 20261204000000_name_check_service_role.sql.
-- Safe to run again.

-- ---------------------------------------------------------------- settings

create table if not exists public.app_settings (
  key   text primary key,
  value text not null
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
grant all on public.app_settings to service_role;
insert into public.app_settings(key, value) values ('require_linkedin', 'true') on conflict (key) do nothing;

-- ---------------------------------------------------------------- columns

alter table public.members add column if not exists linkedin_verified boolean not null default false;
alter table public.members add column if not exists linkedin_name text not null default '';
do $$ begin
  alter table public.members add constraint members_linkedin_name_len check (length(linkedin_name) <= 200);
exception when duplicate_object then null; end $$;
-- Members may see whether someone is LinkedIn-verified (a badge), not the raw LinkedIn name.
grant select (linkedin_verified) on public.members to authenticated;

-- ---------------------------------------------------------------- the check

-- Lowercase letters only (same alphabets as the name rule), for comparing names.
create or replace function public.name_letters(n text) returns text
language sql immutable set search_path = '' as $$
  select lower(regexp_replace(coalesce(n, ''),
    '[^A-Za-zÀ-ÖØ-öø-ɏЀ-ӿא-תؠ-ي]', '', 'g'));
$$;
revoke execute on function public.name_letters(text) from public, anon, authenticated;
grant execute on function public.name_letters(text) to service_role;

-- True when every word (2+ letters) of first + last appears in the LinkedIn name.
create or replace function public.name_matches_linkedin(first text, last text, li_name text) returns boolean
language sql immutable set search_path = '' as $$
  select public.name_letters(li_name) <> ''
     and exists (select 1 from regexp_split_to_table(coalesce(first,'') || ' ' || coalesce(last,''), '[\s\-]+') w
                 where length(public.name_letters(w)) >= 2)
     and not exists (select 1 from regexp_split_to_table(coalesce(first,'') || ' ' || coalesce(last,''), '[\s\-]+') w
                     where length(public.name_letters(w)) >= 2
                       and position(public.name_letters(w) in public.name_letters(li_name)) = 0);
$$;
revoke execute on function public.name_matches_linkedin(text, text, text) from public, anon, authenticated;
grant execute on function public.name_matches_linkedin(text, text, text) to service_role;

create or replace function public.members_linkedin_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  li  jsonb;
  li_name text;
begin
  -- Only the member acting on their own row is checked.
  if uid is null or uid <> new.id then return new; end if;
  select i.identity_data into li from auth.identities i
   where i.user_id = uid and i.provider = 'linkedin_oidc' order by i.created_at desc nulls last limit 1;
  if li is null then
    if tg_op = 'INSERT' and coalesce((select value from public.app_settings where key = 'require_linkedin'), 'true') = 'true' then
      raise exception 'linkedin-required' using errcode = '42501';
    end if;
    return new;
  end if;
  li_name := left(coalesce(nullif(trim(coalesce(li->>'given_name','') || ' ' || coalesce(li->>'family_name','')), ''),
                           li->>'name', li->>'full_name', ''), 200);
  if not public.name_matches_linkedin(new.first_name, new.last_name, li_name)
     and not public.name_matches_linkedin(new.first_name, new.last_name, li->>'name') then
    raise exception 'linkedin-name-mismatch' using errcode = '22023', detail = li_name;
  end if;
  new.linkedin_verified := true;
  new.linkedin_name := li_name;
  return new;
end $$;
revoke execute on function public.members_linkedin_check() from public, anon, authenticated;

drop trigger if exists members_linkedin_check on public.members;
create trigger members_linkedin_check before insert or update of first_name, last_name on public.members
  for each row execute function public.members_linkedin_check();

-- ---------------------------------------------------------------- admins see it

drop function if exists public.admin_pending_requests();
create function public.admin_pending_requests() returns table (
  id uuid, first_name text, last_name text, headline text, location text, industry text, about text,
  linkedin_url text, join_answer text, signup_source text, created_at timestamptz,
  email text, phone text, school text, class_year int, career jsonb,
  linkedin_verified boolean, linkedin_name text
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
                     where k.member_id = m.id), '[]'::jsonb),
           m.linkedin_verified, m.linkedin_name
      from public.members m
      join public.member_contacts c on c.member_id = m.id
      left join lateral (select ms.school, ms.class_year from public.member_schools ms
                         where ms.member_id = m.id order by ms.sort limit 1) s on true
     where m.status = 'pending'
     order by m.created_at;
end $$;
revoke execute on function public.admin_pending_requests() from public, anon;
grant execute on function public.admin_pending_requests() to authenticated;

-- Rollback:
-- drop trigger if exists members_linkedin_check on public.members;
-- update public.app_settings set value = 'false' where key = 'require_linkedin';   -- or just this, to pause the rule
-- (the columns, settings table and admin function's two extra columns are harmless to leave)
