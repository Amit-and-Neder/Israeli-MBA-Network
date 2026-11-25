-- Ba-mba: "is this email already registered?" counts only people who have a profile or a join request.
--
-- Signing in with LinkedIn creates a Supabase login even for someone who never signed up (Supabase does that
-- for every successful OAuth login; the site then signs them out with "Sign up first"). Those empty logins made
-- email_in_use() return true, so the person was told "This email already has an account" when they then tried
-- to sign up (seen 2026-11-25). Now only logins with a members row count. Signing up afterwards reuses the same
-- login, so no duplicate account is created.
--
-- Same rate limit as 20261203000000_security_hardening.sql (20 an hour per visitor, 500 in total).
-- Run once, after 20261205000000_linkedin_verification.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

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
  return exists (select 1 from auth.users u join public.members m on m.id = u.id
                  where lower(u.email) = lower(trim(email_in_use.email)));
end $$;
revoke execute on function public.email_in_use(text) from public;
grant execute on function public.email_in_use(text) to anon, authenticated;

-- Rollback: re-run the email_in_use() definition from 20261203000000_security_hardening.sql.
