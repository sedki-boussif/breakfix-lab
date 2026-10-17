#!/usr/bin/env bash
# s5-08 — check: both faults, not just the reported one. All three apps answer,
# through the proxy, with the database running.
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

db_unit="${DB_UNIT:-postgresql.service}"
ctl_unit='lab-absence-control-failing.service'

# Fault one.
assert_cmd "the nginx configuration is valid" lab_as_root nginx -t
assert_cmd "nginx is running" systemctl is-active --quiet nginx

# Fault two.
assert_cmd "the database is running" systemctl is-active --quiet "$db_unit"

# All three, not just the one that was reported.
assert_http "stages answers" "${STAGES_URL:?}" 200
assert_http "leaves answers" "${LEAVES_URL:?}" 200
assert_http "the theses API answers" "${NURSE_API:?}" 200

# And through the proxy, so removing a vhost to silence the 502 does not pass.
if [[ -n "${LEAVES_VHOST:-}" ]]; then
  assert_cmd "leaves answers through the host nginx" \
    curl -fsS -o /dev/null --max-time 10 -H "Host: ${LEAVES_VHOST}" \
    "http://127.0.0.1/etoile-formation-conge/"
else
  printf 'SKIP  LEAVES_VHOST is not set, so the proxy path was not checked\n'
fi

# Absence, with the detector proved against a unit planted to fail.
detect_failed_unit() {
  systemctl list-units --state=failed --no-legend --plain 2>/dev/null | grep -q .
}
plant_failed_unit() {
  lab_as_root systemd-run --unit="${ctl_unit%.service}" --quiet \
    -p Type=oneshot -p RemainAfterExit=no /bin/false >/dev/null 2>&1 || true
  sleep 2
}
clean_failed_unit() {
  lab_as_root systemctl reset-failed "$ctl_unit" >/dev/null 2>&1 || true
  sleep 1
}
assert_absent "no unit is left in a failed state" \
  detect_failed_unit plant_failed_unit clean_failed_unit

assert_summary
