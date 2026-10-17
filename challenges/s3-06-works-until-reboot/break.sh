#!/usr/bin/env bash
# s3-06 — break: nurse loses its restart policy. Everything keeps working until
# the daemon or the machine restarts.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-06-works-until-reboot'

if [[ "$(svc_mode nurse)" == "compose" ]]; then
  override="${NURSE_DIR:?}/compose.override.yaml"
  if [[ -f "$override" ]]; then
    lab_backup_file "$ID" "$override"
  else
    lab_state_set "$ID" CREATED_OVERRIDE 1
  fi
  {
    printf 'services:\n'
    for svc in "$(svc_name nurse api)" "$(svc_name nurse web)"; do
      printf '  %s:\n    restart: "no"\n' "$svc"
    done
  } >"$override"
  svc_compose nurse up -d >/dev/null 2>&1 || true
else
  lab_as_root systemctl disable "$(svc_name nurse api)" >/dev/null 2>&1 || true
  lab_as_root systemctl disable "$(svc_name nurse web)" >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
