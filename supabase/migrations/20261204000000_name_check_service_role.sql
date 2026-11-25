-- Israeli MBA Network: fix for 20261202000000_name_validation.sql.
--
-- The members table's name rule (constraint members_name_chars and trigger members_check_name) calls
-- public.valid_person_name(). That file revoked EXECUTE on it from everyone, so any write to members by the
-- email function (it uses the service_role key) failed with "permission denied for function valid_person_name".
-- That broke: the "new request" email to admins, the Approve/Decline buttons in that email, and welcome emails.
-- Writes through the app's own functions (submit_join_request, update_my_profile, admin_decide) were not
-- affected: they run as the owner.
--
-- valid_person_name only checks a string's characters and length; it reads no data. Members still can't call it.
--
-- Run once, after 20261203000000_security_hardening.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

grant execute on function public.valid_person_name(text) to service_role;

-- Rollback (undoes the fix and brings the bug back):
-- revoke execute on function public.valid_person_name(text) from service_role;
