#!/usr/bin/env bash
# s7-05 — check: backups run again, AND the thing that should have told you
# three weeks ago now actually fires. Restoring the backup without restoring
# the ability to notice is the trap.
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

ID='s7-05-backups-stopped'
timer="${BACKUP_TIMER:?}"; marker="${BACKUP_MARKER:?}"
alog="${BACKUP_ALERT_LOG:?}"; report="$LAB_ROOT/reports/${ID}.md"

# Backups are running again.
assert_cmd "the backup timer is enabled" systemctl is-enabled --quiet "$timer"
assert_cmd "the backup timer is active" systemctl is-active --quiet "$timer"

# And the marker reflects a real recent run.
health_file_fresh "the success marker is fresh" "$marker" "${BACKUP_MAX_AGE_H:-30}"

# The half everybody forgets: the dead-man's-switch has to fire. Induce the
# state and require a NEW line, so a line that was already there does not count.
before="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
saved="$(lab_state_dir "$ID")/marker-mtime"
lab_as_root stat -c '%Y' "$marker" >"$saved" 2>/dev/null || true
lab_as_root systemctl stop "$timer" >/dev/null 2>&1 || true
lab_as_root touch -d '21 days ago' "$marker" 2>/dev/null || true
lab_as_root systemctl start "${BACKUP_WATCH_SERVICE:-lab-backup-watch.service}" >/dev/null 2>&1 || true
sleep 20
after="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
if (( after > before )); then
  assert_pass "a three-week-old marker produces an alert (${alog} grew)"
else
  assert_fail "a three-week-old marker produces an alert" \
    "nothing new in ${alog}. Backups running again with blind monitoring means the next gap is also three weeks"
fi
# Put it back whatever happened.
[[ ! -s "$saved" ]] || lab_as_root touch -d "@$(cat "$saved")" "$marker" 2>/dev/null || true
lab_as_root systemctl start "$timer" >/dev/null 2>&1 || true

if [[ -f "$report" ]]; then
  assert_file_matches "the report explains the three-week gap" \
    "$report" '[Tt]hree week|21 day|gap|silent'
else
  assert_fail "the report exists" "lab report ${ID}   # why did nobody know for three weeks?"
fi

assert_summary
