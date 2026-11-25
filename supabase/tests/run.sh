#!/usr/bin/env bash
# Runs the privacy tests against a throwaway local database.
# Usage: PGHOST=/tmp PGPORT=5432 PGUSER=postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export PGOPTIONS="-c client_min_messages=warning"
DB=imn_privacy_test
psql -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/supabase_shim.sql
for f in supabase/migrations/*.sql; do psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$f"; done
psql -d "$DB" -v ON_ERROR_STOP=1 -o /dev/null -f supabase/tests/privacy_test.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -o /dev/null -f supabase/tests/contact_sharing_test.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -o /dev/null -f supabase/tests/status_note_test.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -o /dev/null -f supabase/tests/reports_test.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -o /dev/null -f supabase/tests/security_hardening_test.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -o /dev/null -f supabase/tests/member_data_test.sql
psql -d "$DB" -c "select case when ok then 'PASS' else 'FAIL' end as result, msg from t.results order by n" \
     -c "select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.results" | tee /tmp/imn_privacy_test.out
! grep -q '^ FAIL' /tmp/imn_privacy_test.out
