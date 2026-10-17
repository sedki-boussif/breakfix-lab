#!/usr/bin/env bash
# s5-05 — break: one busy loop per core, under an innocuous name. Ordinary
# priority, ordinary user, trivially killable.
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

ID='s5-05-everything-is-slow'
name="${S5_SPIN_NAME:-apt-cache-gen}"
pidfile="$(lab_state_dir "$ID")/spinners.pids"
want="$(nproc)"

# Idempotent: top up to one per core, never beyond.
alive=0
if [[ -f "$pidfile" ]]; then
  while read -r pid; do
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && alive=$(( alive + 1 ))
  done <"$pidfile"
fi

if (( alive < want )); then
  for _ in $(seq 1 $(( want - alive ))); do
# Values are passed as positional parameters rather than interpolated
# into the script text: safer, and $1/$2 below are deliberate.
# shellcheck disable=SC2016
    setsid bash -c 'exec -a "$1" bash -c "while :; do :; done"' _ "$name" &
    echo $! >>"$pidfile"
  done
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
