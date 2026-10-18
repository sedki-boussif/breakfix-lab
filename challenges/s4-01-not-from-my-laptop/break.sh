#!/usr/bin/env bash
# s4-01 — break: deny the leave app's port at the firewall, before the allow
# rule. Loopback is untouched, so everything tested on the server works.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-01-not-from-my-laptop'
port="${LEAVES_PORT:-8081}"

command -v ufw >/dev/null 2>&1 || { printf 'ufw is not installed\n' >&2; exit 1; }

# Deny the port the host nginx proxies from the outside world. Inserted at
# position 1 so it precedes any allow rule: ufw is first-match.
if ! lab_as_root ufw status | grep -q "DENY.*${port}"; then
  lab_as_root ufw --force insert 1 deny proto tcp to any port 80 >/dev/null
  lab_state_set "$ID" ADDED_HTTP 1
fi
lab_as_root ufw status numbered >/dev/null 2>&1 || true

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
