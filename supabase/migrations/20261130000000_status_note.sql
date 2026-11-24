-- Israeli MBA Network: a short status note ("speech bubble") each member can write for the network.
--
-- Shown above the member's photo on cards and on their profile. Up to 100 characters, plain text.
-- Approved members and admins see approved members' notes; everyone sees their own.
--
-- Run once, after 20261129000000_contacts_for_members.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

alter table public.members add column if not exists status_note text not null default '';
alter table public.members add column if not exists status_note_at timestamptz;
do $$ begin
  alter table public.members add constraint members_status_note_len check (length(status_note) <= 100);
exception when duplicate_object then null; end $$;

-- Set or clear your own note (an empty note clears it).
create or replace function public.set_my_status(note text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); n text := left(regexp_replace(trim(coalesce(note, '')), '\s+', ' ', 'g'), 100);
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  update public.members
     set status_note = n, status_note_at = case when n = '' then null else now() end, updated_at = now()
   where id = uid and status <> 'declined';
  if not found then raise exception 'no-profile' using errcode = 'P0002'; end if;
end $$;
revoke execute on function public.set_my_status(text) from public, anon;
grant execute on function public.set_my_status(text) to authenticated;

-- Notes the caller may see.
create or replace function public.status_notes()
returns table (member_id uuid, note text, at timestamptz)
language sql stable security definer set search_path = '' as $$
  select m.id, m.status_note, m.status_note_at
    from public.members m
   where m.status_note <> ''
     and (m.id = auth.uid() or ((public.is_approved() or public.is_admin()) and m.status = 'approved'));
$$;
revoke execute on function public.status_notes() from public, anon;
grant execute on function public.status_notes() to authenticated;
