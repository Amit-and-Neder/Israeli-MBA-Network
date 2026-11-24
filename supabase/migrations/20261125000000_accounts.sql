-- Israeli MBA Network: account management. Members log in with email and password (Supabase Auth);
-- this adds the one thing the page can't do by itself: deleting your own account.
--
-- Run once, after 20261124000000_member_data.sql: Supabase -> SQL Editor -> paste this file -> Run.
-- Safe to run again.

-- Deletes the caller's login. Everything tied to it goes with it: their member profile, contacts,
-- schools, career, stars, posts, "interested" marks, intros and admin rights (all "on delete cascade").
-- The page removes the caller's photo files first, because Storage files can't be deleted from SQL.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  -- Members this person approved or declined keep their decision; only the link to the deleted admin goes.
  update public.members set decided_by = null where decided_by = uid;
  delete from auth.users where id = uid;
end $$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
