#!/usr/bin/env bash
# s5-03 — break: a process holds a large deleted file open, so the space is
# gone and no path to it exists.
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

ID='s5-03-deleted-file-held-open'
mnt="$(lab_fs_require logs "${S5_LOGS_MB:-512}")"
# Re-checked independently of the library before anything large is written.
lab_fs_is_ours "$mnt" || { printf 'refusing: %s is not a lab filesystem\n' "$mnt" >&2; exit 1; }
pidfile="$(lab_state_dir "$ID")/holder.pid"

# Idempotent: a holder that is still alive is left alone.
if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  lab_state_set "$ID" BROKEN_AT "$(date +%s)"
  exit 0
fi

lab_as_root mkdir -p "$mnt/leaves"
# A visible, plausible log file first, so there is something to look at.
printf 'rotated at %s\n' "$(date -Is)" | lab_as_root tee "$mnt/leaves/access.log" >/dev/null

big="$mnt/leaves/access.log.1"
fill_k="$(lab_fs_fill_kb "$mnt" 97 "${S5_LOGS_MB:-512}")"
lab_as_root fallocate -l "${fill_k}K" "$big" 2>/dev/null ||
  lab_as_root dd if=/dev/zero of="$big" bs=1K count="$fill_k" status=none

# Open it, unlink it, keep the descriptor. The process execs into sleep rather
# than looping on it: bash defers signal handling while waiting on a foreground
# child, so a looping holder would ignore TERM for up to an hour.
# The holder records its own pid before exec'ing: backgrounding lab_as_root
# would make $! the wrapper's subshell rather than the process that ends up
# holding the descriptor, and every later step needs the real one.
# shellcheck disable=SC2016  # $1 and $2 are the inner script's parameters
lab_as_root bash -c '
  exec 9<"$1"
  rm -f -- "$1"
  echo $$ >"$2"
  exec -a leaves-logwriter sleep infinity
' _ "$big" "$pidfile" &
sleep 1
sleep 2

lab_state_set "$ID" MNT "$mnt"
lab_state_set "$ID" HOLDER "$(cat "$pidfile" 2>/dev/null || true)"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
