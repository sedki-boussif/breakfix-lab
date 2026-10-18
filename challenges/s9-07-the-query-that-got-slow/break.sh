#!/usr/bin/env bash
# s9-07 — break: drop the index the ward filter depends on. Nothing fails; one
# query gets four or five times slower.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s9-07-the-query-that-got-slow'
index="${S9_07_INDEX:-ix_placements_ward_started}"

stages_psql() {
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
      psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-stages_owner}" \
      -d "${POSTGRES_DB:-stages}" "$@" )
}

# Refuse if the table is too small for the fault to be real rather than
# theoretical: below about six thousand rows both plans are under a millisecond.
rows="$(stages_psql -tAq -c 'SELECT count(*) FROM placements' 2>/dev/null | tr -d '[:space:]' || echo 0)"
if [[ "${rows:-0}" -lt 6000 ]]; then
  printf 'refusing: placements has %s rows.\n' "${rows:-0}" >&2
  printf 'Below about 6000 the sequential scan is as fast as the index, so this\n' >&2
  printf 'challenge would have no measurable symptom. Seed it first:\n' >&2
  printf '  bash lib/seed.sh stages\n' >&2
  exit 1
fi

# Record the definition so reset recreates exactly what was there.
def="$(stages_psql -tAq -c "SELECT indexdef FROM pg_indexes WHERE indexname = '${index}'" 2>/dev/null | head -1)"
if [[ -n "$def" ]]; then
  printf '%s;\n' "$def" > "$(lab_state_dir "$ID")/index.sql"
  stages_psql -q -c "DROP INDEX IF EXISTS ${index}" >/dev/null 2>&1 || true
  stages_psql -q -c 'ANALYZE placements' >/dev/null 2>&1 || true
fi

lab_state_set "$ID" INDEX "$index"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
