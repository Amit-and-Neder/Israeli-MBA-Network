-- Israeli MBA Network: first and last names may contain only letters and the few marks real names use.
--
-- Allowed: letters (English and accented Latin, Hebrew, Arabic, Cyrillic), spaces, hyphens, periods and
-- apostrophes (' ’ ׳), as in "Ben-David", "O'Brien", "J. R." or "ג׳ני". A name must start with a letter.
-- Refused: digits and symbols such as ; " ` = < > ( ) * / \ % @ #, and "--".
--
-- This is input hygiene, not the defense against SQL injection: every query already passes names as
-- values, never as SQL text. It keeps junk and attack-looking strings out of member names.
--
-- Run once, after 20261201000000_reports.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

create or replace function public.valid_person_name(n text) returns boolean
language sql immutable set search_path = '' as $$
  select n is not null
     and length(n) between 1 and 80
     and n ~ '^[A-Za-zÀ-ÖØ-öø-ɏЀ-ӿא-תؠ-ي][A-Za-zÀ-ÖØ-öø-ɏЀ-ӿא-תؠ-ي ''’׳.-]*$'
     and n !~ '--';
$$;
revoke execute on function public.valid_person_name(text) from public, anon, authenticated;

-- A clear error ("bad-name") for the page, before the table rule below would refuse it.
create or replace function public.check_member_name() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not public.valid_person_name(new.first_name) or not public.valid_person_name(new.last_name) then
    raise exception 'bad-name' using errcode = '22023';
  end if;
  return new;
end $$;
revoke execute on function public.check_member_name() from public, anon, authenticated;

drop trigger if exists members_check_name on public.members;
create trigger members_check_name before insert or update of first_name, last_name on public.members
  for each row execute function public.check_member_name();

-- The same rule on the table itself, so no path (including server-side code) can store a bad name.
alter table public.members drop constraint if exists members_name_chars;
alter table public.members add constraint members_name_chars
  check (public.valid_person_name(first_name) and public.valid_person_name(last_name));
