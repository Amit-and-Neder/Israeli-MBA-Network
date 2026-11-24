-- Israeli MBA Network: members can report a profile to the admins. There is no blocking.
--
-- A report is private: only admins see it, and the reported member is never told who reported them.
-- Admins review open reports in the app and mark them resolved.
--
-- Run once, after 20261130000000_status_note.sql: Supabase -> SQL Editor -> paste this file -> Run. Safe to run again.

create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.members(id) on delete cascade,
  reported_id  uuid not null references public.members(id) on delete cascade,
  reason       text not null check (reason in ('fake','spam','inappropriate','harassment','other')),
  details      text not null default '' check (length(details) <= 1000),
  status       text not null default 'open' check (status in ('open','resolved')),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references auth.users(id) on delete set null,
  check (reporter_id <> reported_id)
);
create index if not exists reports_open_idx on public.reports(status, created_at desc);
alter table public.reports enable row level security;
-- No policies and no grants: members never read or write the table directly.
revoke all on public.reports from anon, authenticated;
grant all on public.reports to service_role;

-- Report an approved member. Up to 10 reports a day per member.
create or replace function public.report_member(member uuid, reason text, details text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not-logged-in' using errcode = '28000'; end if;
  if not public.is_approved() then raise exception 'not-approved' using errcode = '42501'; end if;
  if member = uid then raise exception 'self-report' using errcode = '22023'; end if;
  if not exists (select 1 from public.members where id = member and status = 'approved') then
    raise exception 'no-member' using errcode = 'P0002';
  end if;
  if reason is null or reason not in ('fake','spam','inappropriate','harassment','other') then
    raise exception 'bad-reason' using errcode = '22023';
  end if;
  if (select count(*) from public.reports where reporter_id = uid and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'too-many' using errcode = 'P0001';
  end if;
  insert into public.reports(reporter_id, reported_id, reason, details)
  values (uid, member, reason, left(trim(coalesce(details, '')), 1000));
end $$;
revoke execute on function public.report_member(uuid, text, text) from public, anon;
grant execute on function public.report_member(uuid, text, text) to authenticated;

-- Admins: open reports (and the last 30 days of resolved ones), newest first, with names.
create or replace function public.admin_reports()
returns table (id uuid, status text, reason text, details text, created_at timestamptz,
               reported_id uuid, reported_name text, reporter_id uuid, reporter_name text, open_count bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'not-admin' using errcode = '42501'; end if;
  return query
    select r.id, r.status, r.reason, r.details, r.created_at,
           r.reported_id, (d.first_name || ' ' || d.last_name),
           r.reporter_id, (p.first_name || ' ' || p.last_name),
           (select count(*) from public.reports x where x.reported_id = r.reported_id and x.status = 'open')
      from public.reports r
      join public.members d on d.id = r.reported_id
      join public.members p on p.id = r.reporter_id
     where r.status = 'open' or r.resolved_at > now() - interval '30 days'
     order by (r.status = 'open') desc, r.created_at desc;
end $$;
revoke execute on function public.admin_reports() from public, anon;
grant execute on function public.admin_reports() to authenticated;

create or replace function public.admin_resolve_report(report uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'not-admin' using errcode = '42501'; end if;
  update public.reports set status = 'resolved', resolved_at = now(), resolved_by = auth.uid()
   where id = report and status = 'open';
  if not found then raise exception 'not-open' using errcode = 'P0002'; end if;
end $$;
revoke execute on function public.admin_resolve_report(uuid) from public, anon;
grant execute on function public.admin_resolve_report(uuid) to authenticated;
