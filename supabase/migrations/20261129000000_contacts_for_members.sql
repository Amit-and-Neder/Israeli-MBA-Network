-- Israeli MBA Network: shared contact details are open to every approved member. No intro needed.
--
-- Each member shares their email, their WhatsApp number, or both (20261128000000_contact_sharing.sql).
-- Every approved member, and every admin, sees what each approved member shares. A WhatsApp number
-- counts as shared when it's filled in; an email when share_email is on.
-- Pending, declined and logged-out users still see only their own details.
--
-- Run once, after 20261128000000_contact_sharing.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

create or replace function public.visible_contacts()
returns table (member_id uuid, email text, phone text, share_email boolean)
language sql stable security definer set search_path = '' as $$
  select c.member_id,
         case when c.share_email or c.member_id = auth.uid() or public.is_admin() then c.email::text else '' end,
         c.phone,
         c.share_email
    from public.member_contacts c
    join public.members m on m.id = c.member_id
   where c.member_id = auth.uid()
      or public.is_admin()
      or (public.is_approved() and m.status = 'approved');
$$;
revoke execute on function public.visible_contacts() from public, anon;
grant execute on function public.visible_contacts() to authenticated;
