#!/usr/bin/env bash
# s9-07 — reset: recreate the index exactly as it was.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s9-07-the-query-that-got-slow'
sql="$(lab_state_dir "$ID")/index.sql"

if [[ -s "$sql" ]]; then
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
      psql -q -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" ) <"$sql" >/dev/null 2>&1 || true
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
      psql -q -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" \
      -c 'ANALYZE placements' ) >/dev/null 2>&1 || true
fi
lab_state_set "$ID" BROKEN_AT 0
