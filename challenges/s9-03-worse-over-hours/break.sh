#!/usr/bin/env bash
# s9-03 — break: something appends to a log at a few megabytes a minute. At
# minute one there is no symptom at all.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"

ID='s9-03-worse-over-hours'
pidfile="$(lab_state_dir "$ID")/writer.pid"

# Bounded, like every other growth in this lab: its own filesystem, so the
# accumulation cannot reach anything that matters.
mnt="$(lab_fs_require growth "${S9_03_MB:-512}")"
lab_fs_is_ours "$mnt" || { printf 'refusing: %s is not a lab filesystem\n' "$mnt" >&2; exit 1; }
target="$mnt/leaves/debug.log"
lab_as_root mkdir -p "$(dirname "$target")"

# Idempotent: one writer.
if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  lab_state_set "$ID" BROKEN_AT "$(date +%s)"
  exit 0
fi

# A plausible-looking debug logger. Writes ~2 MB a minute and nothing else.
# shellcheck disable=SC2016  # $1 and $2 are the inner script's parameters
lab_as_root bash -c '
  echo $$ >"$2"
  exec -a "leaves-debug-writer" bash -c "
    while :; do
      printf \"%s DEBUG request trace: %s\n\" \"\$(date -Is)\" \"\$(head -c 512 /dev/urandom | base64 -w0)\" >> \"\$1\"
      sleep 0.05
    done
  " _ "$1"
' _ "$target" "$pidfile" &
sleep 2

lab_state_set "$ID" TARGET "$target"
lab_state_set "$ID" MNT "$mnt"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
