#!/usr/bin/env bash
# s9-04 — check: the process has been alive long enough, and the restart
# counter has stopped moving. A service you just restarted cannot pass.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

unit="$(svc_name leaves web)"
min_up="${S9_04_MIN_UPTIME:-300}"
watch="${S9_04_WATCH:-180}"

assert_cmd "the service is running" systemctl is-active --quiet "$unit"
assert_http "the leave app answers" "${LEAVES_URL:?}" 200

# How long the CURRENT main process has been alive. This is the number that
# distinguishes "up" from "up since four minutes ago, for the fortieth time".
since="$(systemctl show -p ActiveEnterTimestamp --value "$unit" 2>/dev/null || true)"
if [[ -z "$since" ]]; then
  assert_fail "the service's uptime can be read" "systemctl show -p ActiveEnterTimestamp ${unit}"
else
  up=$(( $(date +%s) - $(date -d "$since" +%s 2>/dev/null || echo 0) ))
  assert_above "the service has been up for more than ${min_up}s" "$up" "$min_up" "s"
fi

# And the counter has stopped moving, watched rather than sampled.
before="$(systemctl show -p NRestarts --value "$unit" 2>/dev/null || echo unknown)"
printf 'watching the restart counter for %ss (it is at %s)...\n' "$watch" "$before"
sleep "$watch"
after="$(systemctl show -p NRestarts --value "$unit" 2>/dev/null || echo unknown)"
assert_equal "the restart counter did not move in ${watch}s (${before})" "$after" "$before"

# Nothing is still scheduled to interfere with it.
if systemctl list-timers --all --no-legend 2>/dev/null | grep -q 'lab-s9-04-flap'; then
  assert_fail "nothing is scheduled to kill the service" \
    "the lab-s9-04-flap timer is still present: systemctl list-timers --all"
else
  assert_pass "nothing is scheduled to kill the service"
fi

assert_summary
