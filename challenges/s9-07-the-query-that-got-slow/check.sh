#!/usr/bin/env bash
# s9-07 — check: the PLAN, not only the time. A fix that is fast for the wrong
# reason — a cache, a LIMIT, a denormalised column — fails here.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s9-07-the-query-that-got-slow'
report="$LAB_ROOT/reports/${ID}.md"
q="SELECT count(*) FROM placements WHERE ward = 'Ward Echo' AND started_on > CURRENT_DATE - 200"

stages_psql() {
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
      psql -tAq -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" "$@" )
}

assert_http "stages still answers" "${STAGES_URL:?}" 200

plan="$(stages_psql -c "EXPLAIN (ANALYZE) ${q}" 2>/dev/null || true)"
if [[ -z "$plan" ]]; then
  assert_fail "the query plan can be read" "is the stages database up? docker compose -p stages ps"
  assert_summary
  exit $?
fi

if grep -qiE 'Index (Only )?Scan|Bitmap Index Scan' <<<"$plan"; then
  assert_pass "the planner uses an index for the ward filter"
else
  assert_fail "the planner uses an index for the ward filter" \
    "the plan is still a sequential scan: $(grep -iE 'Scan' <<<"$plan" | head -1 | sed 's/^ *//')"
fi
if grep -qi 'Seq Scan on placements' <<<"$plan"; then
  assert_fail "the plan no longer scans the whole table" \
    "Seq Scan on placements is still in the plan"
else
  assert_pass "the plan no longer scans the whole table"
fi

# Both columns, in order. An index on ward alone improves the time and leaves
# the ordering half scanning.
idx="$(stages_psql -c "SELECT indexdef FROM pg_indexes WHERE tablename='placements'" 2>/dev/null || true)"
if grep -qiE '\(ward[^)]*started_on' <<<"$idx"; then
  assert_pass "an index covers (ward, started_on) together"
else
  assert_fail "an index covers (ward, started_on) together" \
    "found: $(tr '\n' ' ' <<<"$idx")— the query filters on both, so the index needs both"
fi

# And it is actually quick, from the application's side.
t="$(curl -sS -o /dev/null -w '%{time_total}' --max-time 10 \
     "${STAGES_URL%/}/api/placements/?ward=Ward%20Echo" 2>/dev/null || echo 99)"
assert_below "the filtered endpoint answers quickly" "$t" 0.5 "s"

if [[ -f "$report" ]]; then
  assert_file_matches "the report records the execution time before and after" \
    "$report" '[0-9]+(\.[0-9]+)? ?ms|before|after'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the ratio is what justifies the index to whoever asks why it exists"
fi

assert_summary
