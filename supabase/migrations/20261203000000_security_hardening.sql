-- Israeli MBA Network: security hardening from the pre-launch review.
--
--  1. Members read only the public columns of other members. The sign-up answer, sign-up source, who
--     approved them and email bookkeeping stay private (admins still see them through admin functions).
--  2. Size limits on every free-text field and list, so one account can't bloat the directory for everyone.
--  3. The "is this email already registered?" check (used by the sign-up form before it sends a code) is
--     limited per visitor, so nobody can test long lists of emails to find out who is a member.
--
-- Run once, after 20261201000000_reports.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

-- ---------------------------------------------------------------- 1. private member columns

revoke select on public.members from authenticated;
grant select (id, status, first_name, last_name, headline, location, industry, about, contact_pref, can_refer,
              unit, il_university, hometown, topics, photo_path, linkedin_url, created_at, updated_at,
              status_note, status_note_at)
  on public.members to authenticated;

-- ---------------------------------------------------------------- 2. size limits

-- Text lengths. (first/last name, headline, about and join_answer already have limits from earlier files.)
alter table public.members drop constraint if exists members_field_sizes;
alter table public.members add constraint members_field_sizes check (
  length(location) <= 120 and length(industry) <= 80 and length(unit) <= 120
  and length(il_university) <= 120 and length(hometown) <= 120 and length(linkedin_url) <= 300
  and cardinality(topics) <= 20 and length(array_to_string(topics, '')) <= 20 * 60);

alter table public.career drop constraint if exists career_field_sizes;
alter table public.career add constraint career_field_sizes check (length(role) <= 160 and length(location) <= 160);

alter table public.member_schools drop constraint if exists member_schools_field_sizes;
alter table public.member_schools add constraint member_schools_field_sizes check (
  length(school) <= 80 and length(program) <= 60 and length(concentration) <= 120
  and cardinality(clubs) <= 20 and length(array_to_string(clubs, '')) <= 20 * 80);

alter table public.companies drop constraint if exists companies_name_size;
alter table public.companies add constraint companies_name_size check (length(name) between 1 and 160);

-- How many rows one member can have: up to 40 jobs and 5 schools.
create or replace function public.limit_member_rows() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'career' and (select count(*) from public.career where member_id = new.member_id) >= 40 then
    raise exception 'too-many-rows' using errcode = '22023';
  end if;
  if tg_table_name = 'member_schools' and (select count(*) from public.member_schools where member_id = new.member_id) >= 5 then
    raise exception 'too-many-rows' using errcode = '22023';
  end if;
  return new;
end $$;
revoke execute on function public.limit_member_rows() from public, anon, authenticated;

drop trigger if exists career_row_limit on public.career;
create trigger career_row_limit before insert on public.career for each row execute function public.limit_member_rows();
drop trigger if exists member_schools_row_limit on public.member_schools;
create trigger member_schools_row_limit before insert on public.member_schools for each row execute function public.limit_member_rows();

-- ---------------------------------------------------------------- 3. limit the email check

-- One row per check, by visitor address. Nobody reads it through the API; rows older than a day are removed.
create table if not exists public.email_checks (
  ip  text not null,
  at  timestamptz not null default now()
);
create index if not exists email_checks_ip_idx on public.email_checks(ip, at);
create index if not exists email_checks_at_idx on public.email_checks(at);
alter table public.email_checks enable row level security;
revoke all on public.email_checks from anon, authenticated;
grant all on public.email_checks to service_role;

-- Same answer as before (true/false for one address), but at most 20 checks an hour from one visitor
-- and 500 an hour in total. Past that it raises "rate-limit"; the sign-up form then just carries on,
-- and sign-up itself still refuses an email that is taken.
create or replace function public.email_in_use(email text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  h  json := nullif(current_setting('request.headers', true), '')::json;
  v_ip text := coalesce(nullif(h ->> 'cf-connecting-ip', ''), nullif(h ->> 'x-real-ip', ''),
                      nullif(trim(split_part(h ->> 'x-forwarded-for', ',', 1)), ''), 'unknown');
begin
  delete from public.email_checks where at < now() - interval '1 day';
  if (select count(*) from public.email_checks where email_checks.ip = v_ip and at > now() - interval '1 hour') >= 20
     or (select count(*) from public.email_checks where at > now() - interval '1 hour') >= 500 then
    raise exception 'rate-limit' using errcode = 'P0001';
  end if;
  insert into public.email_checks(ip) values (v_ip);
  return exists (select 1 from auth.users u where lower(u.email) = lower(trim(email_in_use.email)));
end $$;
revoke execute on function public.email_in_use(text) from public;
grant execute on function public.email_in_use(text) to anon, authenticated;
