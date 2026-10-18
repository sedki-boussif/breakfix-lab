#!/usr/bin/env bash
# s9-05 — break: change the system timezone. Every OnCalendar timer on the
# machine moves with it, which is not obvious from any symptom.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s9-05-someone-changed-something'
new_tz="${S9_05_TZ:-Europe/Tunis}"

was="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo UTC)"
[[ -n "$(lab_state_get "$ID" WAS_TZ '')" ]] || lab_state_set "$ID" WAS_TZ "$was"

lab_as_root timedatectl set-timezone "$new_tz" >/dev/null 2>&1 || {
  printf 'could not set the timezone to %s\n' "$new_tz" >&2; exit 1; }

# And make the symptom concrete: the report is yesterday's, because last
# night's run has not come due in the new local time.
out="${LAB_JOB_OUT:-/var/lib/lab-jobs/report.csv}"
if [[ -e "$out" ]]; then
  lab_as_root touch -d '26 hours ago' "$out"
fi

lab_state_set "$ID" NEW_TZ "$new_tz"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
