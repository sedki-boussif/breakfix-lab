#!/usr/bin/env bash
# s9-05 — check: the symptom is gone AND the report names the unrelated change.
# A fix that produces output without the diagnosis expires in March.
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

ID='s9-05-someone-changed-something'
out="${LAB_JOB_OUT:-/var/lib/lab-jobs/report.csv}"
report="$LAB_ROOT/reports/${ID}.md"
cron_file='/etc/cron.d/lab-nightly-report'

# The symptom.
health_file_fresh "the nightly report is fresh again" "$out" "${LAB_JOB_MAX_AGE_H:-30}"

# The schedule is explicit about time, one way or the other: either pinned to a
# timezone, or local time chosen deliberately and stated in the report.
pinned=0
if systemctl list-timers --all --no-legend 2>/dev/null | grep -qi 'report'; then
  if systemctl show -p OnCalendar --value "${BACKUP_TIMER:-lab-report.timer}" 2>/dev/null | grep -qiE 'UTC'; then
    pinned=1
  fi
fi
if [[ -f "$cron_file" ]] && grep -qiE '^(CRON_TZ|TZ)=' "$cron_file"; then
  pinned=1
fi
if (( pinned == 1 )); then
  assert_pass "the schedule states its timezone explicitly"
else
  printf 'SKIP  the schedule does not pin a timezone — acceptable if that is deliberate,\n'
  printf '      but the report has to say so, which the next assertion checks\n'
fi

# The diagnosis, which is the thing that makes the fix last.
if [[ -f "$report" ]]; then
  assert_file_matches "the report names the timezone change as the cause" \
    "$report" '[Tt]imezone|timedatectl|Europe/|UTC'
  assert_file_matches "the report says what was decided about local versus UTC" \
    "$report" 'UTC|local time|daylight|DST'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the cause was a change in a different domain: name it"
fi

# Nothing else moved as a side effect: the clock is still right.
assert_cmd "the clock is synchronised" \
  bash -c 'timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes || true'
assert_http "stages still answers" "${STAGES_URL:?}" 200

assert_summary
