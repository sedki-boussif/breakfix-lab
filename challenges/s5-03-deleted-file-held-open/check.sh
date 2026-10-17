#!/usr/bin/env bash
# s5-03 — check: the space is back, nothing holds a deleted file on that
# volume, and the process that was holding it is still running. Killing it is
# the easy fix and does not pass.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s5-03-deleted-file-held-open'
mnt="$(lab_fs_mnt logs)"
holder="$(lab_state_get "$ID" HOLDER '')"
ctl_pidfile="$(lab_state_dir "$ID")/control.pid"

if ! mountpoint -q "$mnt" 2>/dev/null; then
  printf 'The log filesystem is not mounted at %s.\n' "$mnt" >&2
  printf 'Run: lab reset %s\n' "$ID" >&2
  exit 1
fi

assert_below "the log filesystem has room again" "$(lab_fs_pct "$mnt")" 80 "%"

# A process holding an unlinked file that is STILL CONSUMING SPACE.
#
# The size matters, not the descriptor: the passing fix truncates the file
# through /proc/<pid>/fd/<n>, which frees the blocks while the process keeps the
# descriptor open. An assertion that merely forbade a held deleted file would
# contradict the next one, which requires that process to still be running, and
# could only be satisfied by killing it.
#
# Read from /proc rather than through lsof: no external dependency, and — found
# the hard way — no chance of hanging, which an lsof scan can do when it meets a
# mount it cannot stat.
held_threshold_mb="${S5_HELD_MIN_MB:-16}"
detect_held() {
  local fd target size
  for fd in /proc/[0-9]*/fd/*; do
    target="$(readlink "$fd" 2>/dev/null || true)"
    [[ "$target" == *" (deleted)" ]] || continue
    [[ "$target" == "$mnt"/* ]] || continue
    size="$(stat -Lc '%s' "$fd" 2>/dev/null || echo 0)"
    (( size > held_threshold_mb * 1024 * 1024 )) && return 0
  done
  return 1
}
plant_held() {
  local f="$mnt/.lab-absence-control"
  lab_as_root fallocate -l 32M "$f" 2>/dev/null ||
    lab_as_root dd if=/dev/zero of="$f" bs=1M count=32 status=none
  # shellcheck disable=SC2016  # $1 and $2 are the inner script's parameters
  lab_as_root bash -c '
    exec 9<"$1"
    rm -f -- "$1"
    echo $$ >"$2"
    exec -a lab-absence-control sleep 120
  ' _ "$f" "$ctl_pidfile" &
  sleep 2
}
clean_held() {
  [[ -f "$ctl_pidfile" ]] || return 0
  lab_as_root kill "$(cat "$ctl_pidfile")" 2>/dev/null || true
  rm -f "$ctl_pidfile"; sleep 2
}
assert_absent "no deleted file is still holding space on that filesystem" \
  detect_held plant_held clean_held

# The part that refuses the easy fix.
if [[ -z "$holder" ]]; then
  assert_fail "the process that was holding the file is still running" \
    "no holder was recorded, so this cannot be verified"
elif lab_as_root kill -0 "$holder" 2>/dev/null; then
  assert_pass "the process that was holding the file is still running (pid ${holder})"
else
  assert_fail "the process that was holding the file is still running" \
    "pid ${holder} is gone: killing it returns the space and destroys the evidence. Truncate through /proc/${holder}/fd/<n> instead"
fi

assert_summary
