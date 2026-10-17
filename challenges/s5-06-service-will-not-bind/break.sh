#!/usr/bin/env bash
# s5-06 — break: take the service's port with an unrelated process while the
# service is briefly down, so it cannot bind when it comes back.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s5-06-service-will-not-bind'
port="${LEAVES_PORT:?set LEAVES_PORT in lab.conf}"
name="${S5_DECOY_NAME:-telemetry-agent}"
pidfile="$(lab_state_dir "$ID")/decoy.pid"

# Idempotent: one squatter, not a pile of them.
if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  lab_state_set "$ID" BROKEN_AT "$(date +%s)"
  exit 0
fi

# The service has to let go of the port first, exactly as a deploy would.
svc_stop leaves web >/dev/null 2>&1 || true
sleep 2

# shellcheck disable=SC2016  # $1 and $2 are the inner script's parameters
lab_as_root bash -c '
  echo $$ >"$2"
  exec -a "telemetry-agent" python3 -c "
import socket, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((\"127.0.0.1\", int(\"$1\")))
s.listen(1)
while True:
    time.sleep(3600)
"' _ "$port" "$pidfile" &
sleep 2

# Now try to start it, as he did. It cannot bind.
svc_start leaves web >/dev/null 2>&1 || true

lab_state_set "$ID" DECOY "$(cat "$pidfile" 2>/dev/null || true)"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
