#!/usr/bin/env bash
# s3-03 — reset: restore the environment file, clear the start limit, start it.
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

ID='s3-03-leave-app-wont-start'
lab_restore_file "$ID" "${LEAVES_ENV:?}"
if [[ "$(svc_mode leaves)" == "systemd" ]]; then
  lab_as_root systemctl reset-failed "$(svc_name leaves web)" >/dev/null 2>&1 || true
fi
svc_restart leaves web >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
