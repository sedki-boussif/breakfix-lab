#!/usr/bin/env bash
# s3-06 — reset: give nurse its restart policy back.
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
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-06-works-until-reboot'

if [[ "$(svc_mode nurse)" == "compose" ]]; then
  override="${NURSE_DIR:?}/compose.override.yaml"
  if [[ "$(lab_state_get "$ID" CREATED_OVERRIDE 0)" == 1 ]]; then
    rm -f "$override"
    lab_state_set "$ID" CREATED_OVERRIDE 0
  else
    lab_restore_file "$ID" "$override"
  fi
  svc_compose nurse up -d >/dev/null 2>&1 || true
else
  for u in "$(svc_name nurse api)" "${NURSE_WEB_UNIT:-}"; do
    [[ -n "$u" ]] || continue
    lab_as_root systemctl enable --now "$u" >/dev/null 2>&1 || true
  done
fi

rm -f "$(lab_state_dir "$ID")/armed"
lab_state_set "$ID" BROKEN_AT 0
