#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node scripts/prepare-activation.mjs --check
container="planeta-activation-$RANDOM-$$"
cleanup(){ docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# Local disposable database only, without production credentials or a host port.
docker run -d --rm --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine -c wal_level=logical >/dev/null
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  if [[ "$attempt" == 30 ]]; then echo 'PostgreSQL did not start' >&2; exit 1; fi
  sleep 1
done
psql_local(){ docker exec -i "$container" psql -q -X -U postgres -v ON_ERROR_STOP=1 "$@"; }
psql_local < supabase/tests/bootstrap.sql
psql_local < supabase/activation/01_instalacao_nova.sql
psql_local <<'SQL'
do $$begin
  if to_regprocedure('public.admin_control_snapshot(date)') is null
    or not exists(select 1 from public.products)
    or exists(select 1 from public.online_shop_settings where enabled or delivery_enabled)
    or not exists(select 1 from storage.buckets where id='planeta-product-images')
  then raise exception 'Incomplete or unexpectedly open activation';end if;
end $$;
SQL
# A second install must fail without changing the installed catalogue.
if psql_local < supabase/activation/01_instalacao_nova.sql > /dev/null 2>&1; then
  echo 'The installer accepted an existing installation' >&2; exit 1
fi
psql_local < supabase/activation/00_diagnostico.sql
# Explicitly open the disposable test shop for the existing order suites.
psql_local -c "update public.online_shop_settings set enabled=true,delivery_enabled=true"
# Exercise the installed contract, not just the presence of generated SQL text.
for sql in supabase/tests/rls.sql supabase/tests/advanced.sql supabase/tests/tactical.sql supabase/tests/public_menu.sql supabase/tests/online.sql supabase/tests/admin_control.sql; do
  psql_local < "$sql"
done
echo 'Activation install, repeat refusal and operational SQL suites passed.'
