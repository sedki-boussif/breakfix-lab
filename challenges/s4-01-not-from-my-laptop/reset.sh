#!/usr/bin/env bash
# s4-01 — reset: remove the deny rule, leave the firewall enabled.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-01-not-from-my-laptop'
if [[ "$(lab_state_get "$ID" ADDED_HTTP 0)" == 1 ]]; then
  lab_as_root ufw --force delete deny proto tcp to any port 80 >/dev/null 2>&1 || true
  lab_state_set "$ID" ADDED_HTTP 0
fi
lab_as_root ufw --force enable >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
