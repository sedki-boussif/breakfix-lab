#!/usr/bin/env bash
# s9-04 — reset: remove the timer that was killing it.
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

ID='s9-04-the-flapping-service'
lab_as_root systemctl disable --now lab-s9-04-flap.timer >/dev/null 2>&1 || true
lab_as_root rm -f /etc/systemd/system/lab-s9-04-flap.timer \
                  /etc/systemd/system/lab-s9-04-flap.service
lab_as_root systemctl daemon-reload >/dev/null 2>&1 || true
lab_as_root systemctl reset-failed "$(svc_name leaves web)" >/dev/null 2>&1 || true
svc_restart leaves web >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
