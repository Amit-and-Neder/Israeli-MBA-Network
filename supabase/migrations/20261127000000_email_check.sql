-- Israeli MBA Network: tell the sign-up form early when an email already has an account,
-- so the applicant isn't asked for a password and a code only to be refused at the end.
--
-- Run once, after 20261126000000_email_approval.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.
--
-- It answers only true/false for one exact address, so it reveals no names or other details.

create or replace function public.email_in_use(email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where lower(u.email) = lower(trim(email_in_use.email)));
$$;

revoke execute on function public.email_in_use(text) from public;
grant execute on function public.email_in_use(text) to anon, authenticated;
