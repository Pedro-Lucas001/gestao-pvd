#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local disposable Docker database only; never accept a production database URL.
container="planeta-rls-$RANDOM-$$"
image="postgres:17-alpine"
cleanup(){ docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# No published port and no persistent volume. Authentication bypass is confined
# to this disposable container and is NEVER used by the application.
docker run -d --rm --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust "$image" -c wal_level=logical >/dev/null
for attempt in {1..30}; do
 if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
 if [[ "$attempt" == 30 ]]; then echo 'PostgreSQL did not start' >&2; exit 1; fi
 sleep 1
done
for sql in supabase/tests/bootstrap.sql supabase/migrations/*.sql supabase/seed.sql supabase/tests/rls.sql supabase/tests/advanced.sql supabase/tests/tactical.sql supabase/tests/public_menu.sql supabase/tests/online.sql supabase/tests/admin_control.sql; do
 docker exec -i "$container" psql -q -X -U postgres -v ON_ERROR_STOP=1 < "$sql"
done
