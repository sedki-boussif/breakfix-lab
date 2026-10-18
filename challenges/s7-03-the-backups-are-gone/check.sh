#!/usr/bin/env bash
# s7-03 — check: the data is back, it matches the fingerprint of the snapshot
# it came from, and the report states the loss window actually achieved.
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

ID='s7-03-the-backups-are-gone'
report="$LAB_ROOT/reports/${ID}.md"
fp="${BACKUP_FINGERPRINT:?}"

count_live() {
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
      psql -tAq -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" \
      -c "SELECT count(*) FROM placements" ) 2>/dev/null | tr -d '[:space:]'
}

rows="$(count_live)"
if [[ -z "$rows" || "$rows" == 0 ]]; then
  assert_fail "the placements data is back" \
    "the table is still empty — restore the newest READABLE off-site snapshot, not the newest listed one"
else
  assert_pass "the placements data is back (${rows} rows)"
fi

assert_http "stages answers" "${STAGES_URL:?}" 200
assert_http "the placement count endpoint answers" "${STAGES_URL%/}/api/placements/count/" 200

# The restored data matches the fingerprint of the snapshot it came from. A
# restore that exits zero and returns the wrong dataset is the failure this
# assertion exists for.
want="$(sed -n 's/^placements=//p' "$fp" 2>/dev/null | tr -d '[:space:]')"
if [[ -z "$want" ]]; then
  assert_fail "a fingerprint is available to compare against" \
    "s7-01 item 6: row counts recorded at backup time, in ${fp}"
elif [[ "$rows" == "$want" ]]; then
  assert_pass "the restored row count matches the fingerprint (${want})"
else
  assert_fail "the restored row count matches a fingerprint" \
    "live has ${rows}, the fingerprint says ${want}. If you restored an OLDER snapshot on purpose, put its own fingerprint in ${fp} and say so in the report — that is the loss window"
fi

# The off-site repository is readable again, which means the damage was dealt
# with rather than worked around.
assert_cmd "the off-site repository passes a data check" \
  lab_as_root restic -r "${BACKUP_REMOTE:?}" --password-file "${BACKUP_PASSWORD_FILE:?}" \
  check --read-data-subset=5%

# The finding is the number, not the restore.
if [[ -f "$report" ]]; then
  assert_file_matches "the report states the data loss window actually achieved" \
    "$report" '[Ll]oss window|[Rr]PO|[Dd]ata loss|lost [0-9]'
  assert_file_matches "the report compares it against the objective" \
    "$report" '[Oo]bjective|[Tt]arget|RPO'
else
  assert_fail "the report exists" "lab report ${ID}   # the loss window is the finding"
fi

assert_summary
