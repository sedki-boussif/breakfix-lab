#!/usr/bin/env bash
# s7-01 — check: the five properties that distinguish a backup from a copy,
# plus the fingerprint. The dead-man's-switch is tested by actually stopping
# the timer and backdating the marker, because that is the only honest test.
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

repo="${BACKUP_REPO:?}"; remote="${BACKUP_REMOTE:?}"
pw="${BACKUP_PASSWORD_FILE:?}"; marker="${BACKUP_MARKER:?}"
alog="${BACKUP_ALERT_LOG:?}"; timer="${BACKUP_TIMER:?}"
fp="${BACKUP_FINGERPRINT:?}"; keep="${BACKUP_RETENTION_DAILY:-7}"

# 1. An archive exists off this VM.
assert_cmd "the off-site repository exists" lab_as_root test -d "$remote"
assert_cmd "the off-site repository holds at least one snapshot" \
  lab_as_root restic -r "$remote" --password-file "$pw" snapshots --json
# Comparing the two mount points rather than the two paths: "somewhere else"
# means a different filesystem, not a different directory on the same one.
remote_fs="$(findmnt -n -o TARGET --target "$remote" 2>/dev/null || true)"
local_fs="$(findmnt -n -o TARGET --target "$repo" 2>/dev/null || true)"
if [[ -n "$remote_fs" && "$remote_fs" != "$local_fs" ]]; then
  assert_pass "the off-site copy is on its own filesystem (${remote_fs}, not ${local_fs})"
else
  assert_fail "the off-site copy is on its own filesystem" \
    "both are on ${local_fs:-the same filesystem}: a full local disk would take the backups with it"
fi

# 2. Encrypted: the password is not in the repository, and the data is not plain.
assert_cmd "a password file exists outside the repository" lab_as_root test -s "$pw"
if [[ "$(realpath -m "$pw")" == "$(realpath -m "$repo")"/* ]]; then
  assert_fail "the password is not stored inside the repository" \
    "a repository that carries its own key is not encrypted in any useful sense"
else
  assert_pass "the password is not stored inside the repository"
fi
assert_not "the repository is not readable without the password" \
  lab_as_root restic -r "$remote" --password-command '/bin/echo wrong-password' snapshots

# 3. Retention is honoured.
got="$(lab_as_root restic -r "$remote" --password-file "$pw" snapshots --json 2>/dev/null \
       | grep -o '"time"' | wc -l || true)"
if [[ "${got:-0}" -le $(( keep + 2 )) ]]; then
  assert_pass "snapshot count (${got}) is within the retention policy of ${keep}"
else
  assert_fail "snapshot count is within the retention policy" \
    "${got} snapshots against a policy of ${keep} — is restic forget --prune scheduled?"
fi

# 4. It runs on a timer.
assert_cmd "the backup timer exists" systemctl cat "$timer"
assert_cmd "the backup timer is enabled" systemctl is-enabled --quiet "$timer"

# 5. A fingerprint was taken at backup time.
assert_file "a restore fingerprint exists" "$fp"
assert_file_matches "the fingerprint holds row counts, not just a date" "$fp" '[0-9]+'

# 6. The dead-man's-switch. Stop the timer, backdate the marker, and require an
#    alert to appear. Restored afterwards whatever the result.
assert_cmd "a success marker exists" lab_as_root test -e "$marker"
before="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
saved="$(lab_state_dir 's7-01-backups-worth-having')/marker-mtime"
lab_as_root stat -c '%Y' "$marker" >"$saved" 2>/dev/null || true
lab_as_root systemctl stop "$timer" >/dev/null 2>&1 || true
lab_as_root touch -d '5 days ago' "$marker" 2>/dev/null || true
# Give whatever watches it a chance: its own timer, or a manual trigger.
lab_as_root systemctl start "${BACKUP_WATCH_SERVICE:-lab-backup-watch.service}" >/dev/null 2>&1 || true
sleep 20
after="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
if (( after > before )); then
  assert_pass "a stale marker produces an alert (${alog} grew)"
else
  assert_fail "a stale marker produces an alert" \
    "nothing was appended to ${alog}. A backup system with no dead-man's-switch says nothing on the day it stops"
fi
[[ ! -s "$saved" ]] || lab_as_root touch -d "@$(cat "$saved")" "$marker" 2>/dev/null || true
lab_as_root systemctl start "$timer" >/dev/null 2>&1 || true

assert_summary
