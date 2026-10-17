#!/usr/bin/env bash
# s5-04 — reset: remove the limit and stop the hog.
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

ID='s5-04-api-keeps-dying'
pidfile="$(lab_state_dir "$ID")/hog.pid"

if [[ -f "$pidfile" ]]; then
  pid="$(cat "$pidfile")"
  [[ -z "$pid" ]] || lab_as_root kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
fi
lab_as_root pkill -f "${S5_HOG_NAME:-indexer-warmup}" 2>/dev/null || true

if [[ "$(svc_mode nurse)" == "compose" ]]; then
  override="${NURSE_DIR:?}/compose.override.yaml"
  if [[ "$(lab_state_get "$ID" CREATED_OVERRIDE 0)" == 1 ]]; then
    rm -f "$override"; lab_state_set "$ID" CREATED_OVERRIDE 0
  else
    lab_restore_file "$ID" "$override"
  fi
  svc_compose nurse up -d --force-recreate "$(svc_name nurse api)" >/dev/null 2>&1 || true
else
  dropin="$(lab_state_get "$ID" DROPIN '')"
  [[ -z "$dropin" ]] || lab_as_root rm -f "$dropin"
  lab_as_root systemctl daemon-reload
  svc_restart nurse api >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT 0
