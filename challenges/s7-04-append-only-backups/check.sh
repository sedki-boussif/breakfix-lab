#!/usr/bin/env bash
# s7-04 — check: this machine, as root, must be unable to destroy its own
# backups — and must still be able to add to them.
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

ID='s7-04-append-only-backups'
remote="${BACKUP_REMOTE:?}"; pw="${BACKUP_PASSWORD_FILE:?}"
victim="$(lab_state_get "$ID" VICTIM '')"
sumfile="$(lab_state_dir "$ID")/victim.sha256"
report="$LAB_ROOT/reports/${ID}.md"

if [[ -z "$victim" ]]; then
  printf 'No target recorded. Run: lab start %s\n' "$ID" >&2
  exit 1
fi

# 1 and 2: the deletion is attempted as root, and must fail.
assert_cmd "the archive to protect is still present" lab_as_root test -f "$victim"
assert_not "root cannot delete an existing archive" lab_as_root rm -f "$victim"
assert_cmd "and it is still there after the attempt" lab_as_root test -f "$victim"

if [[ -s "$sumfile" ]]; then
  now="$(lab_as_root sha256sum "$victim" 2>/dev/null | cut -d' ' -f1 || true)"
  assert_equal "the archive is byte-identical, so it was not overwritten either" \
    "$now" "$(cat "$sumfile")"
fi
assert_not "root cannot truncate an existing archive" \
  lab_as_root truncate -s 0 "$victim"

# Deleting a whole directory is the other shape of the same attack.
assert_not "root cannot remove the repository wholesale" \
  lab_as_root rm -rf "$remote/data"
assert_cmd "the repository still has data after that attempt" \
  lab_as_root test -d "$remote/data"

# 3: it still works as a backup destination.
probe="$(lab_state_dir "$ID")/probe"
printf 'append-only probe %s\n' "$(date -Is)" >"$probe"
assert_cmd "a new snapshot can still be written to it" \
  lab_as_root restic -r "$remote" --password-file "$pw" backup --tag lab-probe "$probe"

# 4: retention has to live somewhere that is allowed to delete.
if [[ -f "$report" ]]; then
  assert_file_matches "the report says where retention now runs" \
    "$report" '[Rr]etention|[Pp]rune|[Ff]orget'
  assert_file_matches "the report says what happens if that stops" \
    "$report" '[Ii]f (it|that) stop|grow|unbounded|fill'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # append-only moves pruning elsewhere: say where, and what if it stops"
fi

assert_summary
