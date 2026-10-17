#!/usr/bin/env bash
# s0-00-smoke — break: the status page's wrapper is told to exec an
# interpreter that does not exist, so the process dies and the port closes.
# Idempotent: running twice does not deepen the damage.
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

# Deploy the status page if this is the first run. A challenge seeds what it
# needs; it never assumes a previous challenge left something behind.
mkdir -p "$SVC/www"
printf '<!doctype html><title>lab status</title><h1>lab status: ok</h1>\n' \
  >"$SVC/www/index.html"
if [[ ! -f "$RUN" ]]; then
  cat >"$RUN" <<'WRAPPER'
#!/usr/bin/env bash
# Status page wrapper. Serves the lab's status page on $SMOKE_PORT.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 -m http.server "${1:?port}" --directory "$HERE/www" --bind 127.0.0.1
WRAPPER
  chmod +x "$RUN"
fi
lab_backup_file "$ID" "$RUN"

# Stop whatever is running, quietly.
if [[ -f "$PID" ]] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  kill "$(cat "$PID")" 2>/dev/null || true
  sleep 1
fi

# The fault: an interpreter that is not there.
sed -i 's|^exec .* -m http.server|exec /usr/bin/python3-lab -m http.server|' "$RUN"

# Try to start it, exactly as a reboot or an operator would. It will fail.
: >"$SVC/log"
( nohup bash "$RUN" "$PORT" >>"$SVC/log" 2>&1 & echo $! >"$PID" ) || true
sleep 1

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
lab_state_set "$ID" PORT "$PORT"
