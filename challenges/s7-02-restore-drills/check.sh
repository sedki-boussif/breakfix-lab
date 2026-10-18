#!/usr/bin/env bash
# s7-02 — check: a restore that returned the right data, timed, without
# touching the live copy.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s7-02-restore-drills'
fp="${BACKUP_FINGERPRINT:?}"
report="$LAB_ROOT/reports/${ID}.md"
live_before="$(lab_state_dir "$ID")/live-counts-before"

stages_count() {
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
      psql -tAq -U "${POSTGRES_USER:-stages_owner}" -d "$1" \
      -c "SELECT count(*) FROM placements" ) 2>/dev/null | tr -d '[:space:]'
}

# The fingerprint is the thing being restored against.
assert_file "the backup fingerprint exists" "$fp"

# Drill 2: a throwaway database holding the restored data, counted against the
# fingerprint rather than against the live database.
drill_db="${STAGES_DRILL_DB:-stages_drill}"
restored="$(stages_count "$drill_db")"
if [[ -z "$restored" ]]; then
  assert_fail "a restored copy of the database exists (${drill_db})" \
    "nothing to count — restore the dump into a NEW database rather than over the live one"
else
  assert_pass "a restored copy of the database exists (${drill_db}, ${restored} placements)"
  want="$(sed -n 's/^placements=//p' "$fp" 2>/dev/null | tr -d '[:space:]')"
  if [[ -z "$want" ]]; then
    assert_fail "the fingerprint records a placements count to compare against" \
      "add row counts to ${fp} at backup time: s7-01's standard, item 6"
  else
    assert_equal "the restored row count matches the fingerprint (${want})" "$restored" "$want"
  fi
fi

# Drill 1: a file-level restore landed somewhere that is not the live path.
if [[ -n "$(find /tmp /var/tmp -maxdepth 2 -name 'drill*' -print -quit 2>/dev/null)" ]]; then
  assert_pass "a file-level restore was made to a scratch location"
else
  assert_fail "a file-level restore was made to a scratch location" \
    "restic restore latest --target /tmp/drill --include <path>   # never onto the live path"
fi

# The live data is untouched.
if [[ -s "$live_before" ]]; then
  live_now="$(stages_count "${POSTGRES_DB:-stages}")"
  was="$(sed -n 's/^placements=//p' "$live_before" | tr -d '[:space:]')"
  assert_equal "the live database is untouched (${was} placements before)" "$live_now" "$was"
else
  printf 'SKIP  no before-counts were recorded, so "untouched" cannot be checked\n'
fi

# The times are written down, in the report, where they can be compared later.
if [[ -f "$report" ]]; then
  if grep -qiE '([0-9]+ *(s|sec|seconds|m|min|minutes|h|hours))|[0-9]+:[0-9]{2}' "$report"; then
    assert_pass "the report records elapsed times"
  else
    assert_fail "the report records elapsed times" \
      "an RTO nobody measured is a guess, and under pressure a guess becomes a promise. Add the three times to ${report}"
  fi
  # assert_file_matches takes no flags: the regex carries the case itself.
  assert_file_matches "the report states a recovery time objective to compare against" \
    "$report" '[Oo]bjective|RTO|[Tt]arget|[Rr]ecovery time'
else
  assert_fail "the report exists" "lab report ${ID}   # then fill in the three times"
fi

assert_summary
