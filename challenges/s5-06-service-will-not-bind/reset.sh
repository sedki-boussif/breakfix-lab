#!/usr/bin/env bash
# s5-06 — reset: remove the squatter and start the service.
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
pidfile="$(lab_state_dir "$ID")/decoy.pid"

if [[ -f "$pidfile" ]]; then
  pid="$(cat "$pidfile")"
  [[ -z "$pid" ]] || lab_as_root kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
  sleep 1
fi
lab_as_root pkill -f "${S5_DECOY_NAME:-telemetry-agent}" 2>/dev/null || true
if [[ "$(svc_mode leaves)" == "systemd" ]]; then
  lab_as_root systemctl reset-failed "$(svc_name leaves web)" >/dev/null 2>&1 || true
fi
svc_start leaves web >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
