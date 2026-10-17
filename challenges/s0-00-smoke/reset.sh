#!/usr/bin/env bash
# s0-00-smoke — reset: restore the wrapper and leave the page serving.
# Harmless to run twice.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard

# shellcheck source=/dev/null
[[ -f "$LAB_ROOT/lab.conf" ]] && . "$LAB_ROOT/lab.conf"

ID='s0-00-smoke'
PORT="${SMOKE_PORT:-18099}"
SVC="$(lab_state_dir "$ID")/service"
RUN="$SVC/run.sh"
PID="$SVC/pid"

lab_restore_file "$ID" "$RUN"

if [[ -f "$PID" ]] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  kill "$(cat "$PID")" 2>/dev/null || true
  sleep 1
fi

if [[ -x "$RUN" ]]; then
  ( nohup bash "$RUN" "$PORT" >>"$SVC/log" 2>&1 & echo $! >"$PID" )
  sleep 1
fi

lab_state_set "$ID" BROKEN_AT 0
