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
for sql in supabase/tests/rls.sql supabase/tests/advanced.sql supabase/tests/tactical.sql supabase/tests/public_menu.sql supabase/tests/online.sql supabase/tests/admin_control.sql supabase/tests/delivery.sql supabase/tests/menu_customizations.sql supabase/tests/rpc_privileges.sql; do
  psql_local < "$sql"
done

# Third, incompatible legacy contract: refuse occupied tables and preserve the
# empty structure with its functions and dependencies before the new install.
psql_local -c 'create database planeta_legacy_test'
psql_legacy(){ psql_local -d planeta_legacy_test "$@"; }
sed '/^create role /d' supabase/tests/bootstrap.sql | psql_legacy
psql_legacy <<'SQL'
create table public.profiles(id uuid primary key,full_name text,pin_code text);
create table public.products(id uuid primary key,price numeric);
create table public.ingredients(id uuid primary key);
create table public.technical_sheets(product_id uuid references public.products(id));
create table public.customers(id uuid primary key);
create table public.orders(id uuid primary key);
create table public.order_items(order_id uuid references public.orders(id));
create table public.audit_logs(id uuid primary key);
create function public.anonymize_customer_data(target_phone text) returns boolean language sql security definer as $$select false$$;
insert into public.products values('a0000000-0000-0000-0000-000000000001',10);
SQL
if psql_legacy < supabase/activation/03_transicao_legado_vazio.sql > /dev/null 2>&1; then
  echo 'Legacy transition accepted existing data' >&2; exit 1
fi
psql_legacy <<'SQL'
do $$begin
  if not exists(select 1 from public.products)
    or exists(select 1 from pg_namespace where nspname='planeta_legacy_20261107')
  then raise exception 'Legacy refusal did not preserve the original state';end if;
end $$;
delete from public.products;
SQL
psql_legacy < supabase/activation/03_transicao_legado_vazio.sql
psql_legacy <<'SQL'
do $$begin
  if (select count(*) from information_schema.tables where table_schema='planeta_legacy_20261107')<>8
    or to_regprocedure('planeta_legacy_20261107.anonymize_customer_data(text)') is null
    or to_regprocedure('public.anonymize_customer_data(text)') is not null
    or has_schema_privilege('anon','planeta_legacy_20261107','usage')
    or has_function_privilege('anon','planeta_legacy_20261107.anonymize_customer_data(text)','execute')
  then raise exception 'Legacy structure or privileges were not preserved safely';end if;
end $$;
SQL
psql_legacy -c 'update public.online_shop_settings set enabled=true,delivery_enabled=true'
for sql in supabase/tests/public_menu.sql supabase/tests/online.sql supabase/tests/admin_control.sql supabase/tests/delivery.sql supabase/tests/menu_customizations.sql supabase/tests/rpc_privileges.sql; do
  psql_legacy < "$sql"
done
echo 'Activation, repeat refusal, legacy preservation/refusal and operational SQL suites passed.'
