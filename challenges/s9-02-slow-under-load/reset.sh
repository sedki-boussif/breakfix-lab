#!/usr/bin/env bash
# s9-02 — reset: remove the starvation.
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

ID='s9-02-slow-under-load'
dropin="$(lab_state_get "$ID" DROPIN '')"
override="$(lab_state_get "$ID" OVERRIDE '')"

[[ -z "$dropin" ]] || lab_as_root rm -f "$dropin"
if [[ -n "$override" ]]; then
  lab_as_root rm -f "$override"
  lab_restore_file "$ID" "$override"
fi
lab_as_root systemctl daemon-reload >/dev/null 2>&1 || true
svc_restart nurse api >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
