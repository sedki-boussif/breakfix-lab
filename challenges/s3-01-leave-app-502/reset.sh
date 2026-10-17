#!/usr/bin/env bash
# s3-01 — reset: put the unit back and start the service. Harmless twice.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-01-leave-app-502'
unit="$(svc_name leaves web)"

if [[ "$(svc_mode leaves)" == "systemd" ]]; then
  unit_path="$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null || true)"
  [[ -n "$unit_path" && -f "$unit_path" ]] || unit_path="/etc/systemd/system/${unit}"
  lab_restore_file "$ID" "$unit_path"
  lab_as_root systemctl daemon-reload
  # A unit that hit its start limit refuses to come back without this.
  lab_as_root systemctl reset-failed "$unit" >/dev/null 2>&1 || true
  lab_as_root systemctl restart "$unit" >/dev/null 2>&1 || true
else
  override="${LEAVES_DIR:?}/compose.override.yaml"
  if [[ "$(lab_state_get "$ID" CREATED_OVERRIDE 0)" == 1 ]]; then
    rm -f "$override"
    lab_state_set "$ID" CREATED_OVERRIDE 0
  else
    lab_restore_file "$ID" "$override"
  fi
  svc_compose leaves up -d "$unit" >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT 0
