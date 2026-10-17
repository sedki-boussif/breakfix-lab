#!/usr/bin/env bash
# s5-06 — check: the service owns the configured port and answers on it. A
# hand-started gunicorn, or the app moved to another port, does not pass.
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

port="${LEAVES_PORT:?}"
url="${LEAVES_URL:?}"
unit="$(svc_name leaves web)"
main_pid=""

# The pid holding a port, or nothing.
listener_pid() {
  lab_as_root ss -ltnpH "sport = :$1" 2>/dev/null |
    grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2
}

assert_service "the leave service is running" leaves web
assert_http    "the leave app answers" "$url" 200

pid="$(listener_pid "$port")"
if [[ -z "$pid" ]]; then
  assert_fail "the service is listening on port ${port}" \
    "nothing is listening there — moving the app to another port leaves nginx pointing at this one"
elif [[ "$(svc_mode leaves)" != "systemd" ]]; then
  assert_pass "port ${port} has a listener (pid ${pid})"
elif grep -q "$unit" "/proc/${pid}/cgroup" 2>/dev/null; then
  assert_pass "port ${port} belongs to the service (pid ${pid} is inside ${unit})"
elif main_pid="$(systemctl show -p MainPID --value "$unit" 2>/dev/null)" &&
     [[ -n "$main_pid" && "$main_pid" != 0 ]] &&
     { [[ "$pid" == "$main_pid" ]] || pgrep -P "$main_pid" 2>/dev/null | grep -qx "$pid"; }; then
  assert_pass "port ${port} belongs to the service (pid ${pid} is ${unit}'s main process or its child)"
else
  assert_fail "port ${port} belongs to the service" \
    "pid ${pid} is neither in ${unit}'s cgroup nor its main process: something else owns the port, or gunicorn was started by hand"
fi

# Note on what is NOT asserted here. "No foreign process holds the port" looks
# like an absence claim, but the assertion above is positive and stronger: it
# requires the listener on the configured port to be the service itself, which
# fails if a squatter holds it, if nothing holds it, or if gunicorn was started
# by hand. A positive claim is its own evidence and needs no planted control —
# and an absence assertion pointed at some other port would prove only that the
# detector works, while passing with the squatter still in place.

svc_restart leaves web >/dev/null 2>&1 || true
assert_eventually "it binds again after a restart" 45 \
  curl -fsS -o /dev/null --max-time 5 "$url"

assert_summary
