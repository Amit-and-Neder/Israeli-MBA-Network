-- Minimal stand-in for Supabase's built-in roles and auth schema, so the migration and the
-- privacy tests can run on a plain local Postgres. Never run this on the real Supabase project.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
-- Supabase grants these by default on new tables and functions. (Projects with "automatically expose
-- new tables" turned off skip the table grants; the migration sets table access explicitly either way.)
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
-- New functions: like the live project, service_role does NOT get EXECUTE by default (seen 2026-11-25:
-- "permission denied for function valid_person_name" from the email function). Grant it explicitly where needed.
alter default privileges in schema public grant execute on functions to anon, authenticated;
-- Storage: just enough of Supabase's storage schema for the photo policies.
create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text not null, owner uuid default nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated;
