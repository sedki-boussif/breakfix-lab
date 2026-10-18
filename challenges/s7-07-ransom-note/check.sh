#!/usr/bin/env bash
# s7-07 — check: the uploads are genuinely back from the off-site copy, nothing
# of the attacker's is left, and an incident report exists.
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

ID='s7-07-ransom-note'
path="$(lab_state_get "$ID" PATH_ '')"
report="$LAB_ROOT/reports/${ID}.md"

if [[ -z "$path" || ! -d "$path" ]]; then
  printf 'No uploads path recorded. Run: lab start %s\n' "$ID" >&2
  exit 1
fi

# The files are back, and readable as themselves rather than as noise.
count="$(lab_as_root find "$path" -maxdepth 1 -type f ! -name '*.locked' \
         ! -name 'READ_ME_TO_RECOVER.txt' -printf . 2>/dev/null | wc -c || echo 0)"
if (( count > 0 )); then
  assert_pass "the uploads directory holds ${count} real file(s) again"
else
  assert_fail "the uploads are restored" \
    "nothing but scrambled files. restic -r \${BACKUP_REMOTE} restore latest --target /tmp/restore"
fi

# Nothing of the attacker's left behind — not alongside the recovery.
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
assert_cmd "no .locked files remain" \
  bash -c '[[ -z "$(find "$1" -name "*.locked" -print -quit 2>/dev/null)" ]]' _ "$path"
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
assert_cmd "the ransom note is gone from the uploads path" \
  bash -c '[[ ! -e "$1/READ_ME_TO_RECOVER.txt" ]]' _ "$path"

# The application can use them.
assert_http "stages answers" "${STAGES_URL:?}" 200
name="lab-restore-probe-$$.png"
tmp="$(mktemp)"; printf 'probe\n' >"$tmp"
assert_cmd "an upload still works after the recovery" \
  curl -fsS -o /dev/null --max-time 20 -F "file=@${tmp};filename=${name}" \
  "${STAGES_URL%/}/api/uploads/"
assert_http "and reads back" "${STAGES_URL%/}/api/uploads/${name}/" 200
rm -f "$tmp"

# The database was never the target, so it should be untouched. A responder who
# restored it too has done unnecessary damage.
assert_http "the placement count still answers" "${STAGES_URL%/}/api/placements/count/" 200

# Nothing of the attacker's still running.
if [[ -z "${EXPECTED_PORTS:-}" ]]; then
  printf 'SKIP  EXPECTED_PORTS is not set in lab.conf, so ports were not checked\n'
else
  unexpected=""
  while read -r p; do
    [[ -n "$p" ]] || continue
    [[ " ${EXPECTED_PORTS} " != *" ${p} "* ]] || continue
    unexpected+="${p} "
  done < <(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un)
  if [[ -z "$unexpected" ]]; then
    assert_pass "nothing unexpected is listening"
  else
    assert_fail "nothing unexpected is listening" "unexpected ports: ${unexpected}"
  fi
fi

# The incident report.
if [[ -f "$report" ]]; then
  assert_file_matches "the report states the scope: what was lost and what was not" \
    "$report" '[Ss]cope|database (was|is) (intact|fine)|uploads only|not affected'
  assert_file_matches "the report says where the evidence was preserved" \
    "$report" '[Ee]vidence|preserv|cop(y|ied) the|kept the note'
  assert_file_matches "the report records the recovery source and the loss window" \
    "$report" 'off-site|offsite|snapshot|loss'
else
  assert_fail "an incident report exists" \
    "lab report ${ID}   # scope, evidence, recovery source, loss window, and what you decided about the restart"
fi

assert_summary
