#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
container="planeta-sql-editor-$RANDOM-$$"
cleanup(){ docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run -d --rm --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine -c wal_level=logical >/dev/null
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  if [[ "$attempt" == 30 ]]; then echo 'PostgreSQL did not start' >&2; exit 1; fi
  sleep 1
done
for sql in supabase/tests/bootstrap.sql supabase/sql_editor/planeta_lanches_completo.sql supabase/tests/sql_editor.sql supabase/sql_editor/planeta_lanches_ecossistema.sql supabase/tests/ecossistema.sql; do
  docker exec -i "$container" psql -q -X -U postgres -v ON_ERROR_STOP=1 < "$sql"
done
# Uma segunda execução deve abortar antes de tocar nos objetos existentes.
if docker exec -i "$container" psql -q -X -U postgres -v ON_ERROR_STOP=1 < supabase/sql_editor/planeta_lanches_completo.sql >/tmp/planeta-sql-editor-repeat-$$.log 2>&1; then
  echo 'ERRO: instalação duplicada foi aceita' >&2
  exit 1
fi
rm -f /tmp/planeta-sql-editor-repeat-$$.log
echo 'Proteção contra reinstalação: passou.'
