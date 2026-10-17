#!/usr/bin/env bash
# s0-00-smoke — check: the page answers, and it still answers after the
# service is restarted. A hand-started process that the wrapper cannot
# reproduce does not pass.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

# shellcheck source=/dev/null
[[ -f "$LAB_ROOT/lab.conf" ]] && . "$LAB_ROOT/lab.conf"

ID='s0-00-smoke'
PORT="${SMOKE_PORT:-18099}"
SVC="$(lab_state_dir "$ID")/service"
RUN="$SVC/run.sh"
PID="$SVC/pid"
URL="http://127.0.0.1:${PORT}/"

assert_http "the status page answers" "$URL" 200
assert_http_body "the page is the status page, not a directory listing" "$URL" 'lab status'

# The end state that matters: it comes back on its own after a restart.
if [[ -f "$PID" ]] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  kill "$(cat "$PID")" 2>/dev/null || true
  sleep 1
fi
if [[ -x "$RUN" ]]; then
  ( nohup bash "$RUN" "$PORT" >>"$SVC/log" 2>&1 & echo $! >"$PID" ) || true
fi
assert_eventually "it answers again after a full restart" 20 \
  curl -sS -o /dev/null --max-time 5 "$URL"

assert_summary
