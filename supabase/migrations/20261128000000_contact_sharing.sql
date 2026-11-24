-- Israeli MBA Network: members choose how they're reached after an accepted intro.
--
-- Each member shares their email, their WhatsApp number, or both, and picks one of the shared ones as
-- preferred. Other members only see what is shared, and only after the member accepts their intro.
--
-- Run once, after 20261127000000_email_check.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

alter table public.member_contacts add column if not exists share_email boolean not null default true;

-- Logged-in users may read phone numbers (row rules unchanged) but never the email column directly:
-- emails come through visible_contacts(), which hides the ones their owners chose not to share.
revoke select on public.member_contacts from authenticated;
grant select (member_id, phone, share_email) on public.member_contacts to authenticated;

-- Contact details the caller may see: their own, everyone's for admins, and the people who accepted their intro.
create or replace function public.visible_contacts()
returns table (member_id uuid, email text, phone text, share_email boolean)
language sql stable security definer set search_path = '' as $$
  select c.member_id,
         case when c.share_email or c.member_id = auth.uid() or public.is_admin() then c.email::text else '' end,
         c.phone,
         c.share_email
    from public.member_contacts c
   where c.member_id = auth.uid()
      or public.is_admin()
      or exists (select 1 from public.intro_requests r
                  where r.recipient_id = c.member_id
                    and r.requester_id = auth.uid()
                    and r.status = 'accepted');
$$;
revoke execute on function public.visible_contacts() from public, anon;
grant execute on function public.visible_contacts() to authenticated;

-- Save how you want to be reached: { phone, shareEmail, pref }.
-- At least one of email or WhatsApp must be shared, and the preferred one must be among them.
create or replace function public.update_my_contact(p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  ph  text := coalesce(trim(p->>'phone'), '');
  se  boolean := coalesce((p->>'shareEmail')::boolean, true);
  pr  text := p->>'pref';
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  if pr is null or pr not in ('whatsapp','email') then raise exception 'bad-pref' using errcode = '22023'; end if;
  if not se and ph = '' then raise exception 'share-one' using errcode = '22023'; end if;
  if (pr = 'whatsapp' and ph = '') or (pr = 'email' and not se) then
    raise exception 'pref-not-shared' using errcode = '22023';
  end if;
  update public.member_contacts set phone = ph, share_email = se where member_id = uid;
  if not found then raise exception 'no-profile' using errcode = 'P0002'; end if;
  update public.members set contact_pref = pr, updated_at = now() where id = uid;
end $$;
revoke execute on function public.update_my_contact(jsonb) from public, anon;
grant execute on function public.update_my_contact(jsonb) to authenticated;
