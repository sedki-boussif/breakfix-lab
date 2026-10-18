#!/usr/bin/env bash
# s2-04 — reset: remove the rotations the check forced, and clean up the
# control file the absence assertion plants. The rule itself is the user's work
# and is left alone.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-04-rotate-the-logs'
log="${LEAVES_LOG:-/var/log/leaves/access.log}"
conf="${S2_04_LOGROTATE_CONF:-/etc/logrotate.d/leaves}"
logdir="$(dirname "$log")"
base="$(basename "$log")"
state="$(lab_state_dir "$ID")"

# The planted control, and anything still holding it.
if [[ -s "$state/control-pid" ]]; then
  pkill -P "$(cat "$state/control-pid")" 2>/dev/null || true
  kill "$(cat "$state/control-pid")" 2>/dev/null || true
  rm -f "$state/control-pid"
fi
lab_as_root rm -f "${log}.s2-04-control"

# The rotations, and only things that look like rotations of this one log.
n=0
while read -r f; do
  [[ -n "$f" ]] || continue
  lab_as_root rm -f "$f"
  n=$(( n + 1 ))
done < <(lab_as_root find "$logdir" -maxdepth 1 -name "${base}.*" ! -name "$base" 2>/dev/null || true)
printf 'Removed %s rotated file(s) alongside %s.\n' "$n" "$log"

printf '\n%s was left alone — the rule is your work, not the lab'"'"'s.\n' "$conf"
printf 'To start it over yourself:\n  sudo rm %s\n' "$conf"
lab_state_set "$ID" BROKEN_AT 0
