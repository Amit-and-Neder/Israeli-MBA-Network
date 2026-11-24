-- Israeli MBA Network: approve or decline join requests straight from the admin email.
--
-- Each pending request gets a private one-time key. The "new request" email to the admins carries it in its
-- Approve and Decline buttons; the email function checks the key, records the decision and deletes the key.
-- Nobody can read the keys through the API: the table has no policies and no grants, so only the email
-- function (with its server-side key) sees them.
--
-- Run once, after 20261125000000_accounts.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

create table if not exists public.review_tokens (
  member_id  uuid primary key references public.members(id) on delete cascade,
  token      text not null default replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now()
);
alter table public.review_tokens enable row level security;
revoke all on public.review_tokens from anon, authenticated;
grant all on public.review_tokens to service_role;

-- Every new pending request gets a key. (A re-submitted request keeps its key.)
create or replace function public.new_review_token() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'pending' then
    insert into public.review_tokens(member_id) values (new.id) on conflict (member_id) do nothing;
  end if;
  return new;
end $$;
revoke execute on function public.new_review_token() from public, anon, authenticated;

drop trigger if exists members_review_token on public.members;
create trigger members_review_token after insert on public.members
  for each row execute function public.new_review_token();

-- Requests already waiting when this runs get a key too.
insert into public.review_tokens(member_id)
  select id from public.members where status = 'pending'
  on conflict (member_id) do nothing;

-- Once an admin decides in the app, the emailed buttons stop working.
create or replace function public.drop_review_token() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'pending' then delete from public.review_tokens where member_id = new.id; end if;
  return new;
end $$;
revoke execute on function public.drop_review_token() from public, anon, authenticated;

drop trigger if exists members_drop_review_token on public.members;
create trigger members_drop_review_token after update of status on public.members
  for each row execute function public.drop_review_token();
