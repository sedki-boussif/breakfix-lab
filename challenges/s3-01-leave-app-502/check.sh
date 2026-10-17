#!/usr/bin/env bash
# s3-01 — check: the app answers, it answers through the proxy, and it still
# answers after the service manager restarts it. A gunicorn started by hand
# passes the first two and fails the last, which is the point.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

url="${LEAVES_URL:?set LEAVES_URL in lab.conf}"

assert_service "the leave service is running" leaves web
assert_http    "the leave app answers" "$url" 200
assert_cmd     "the login page under the prefix is reachable" \
               curl -fsS -o /dev/null --max-time 10 "${url%/}/login/"

# Through the host nginx, with the Host header the vhost expects, so the 502
# the ticket described is demonstrably gone rather than merely bypassed.
if [[ -n "${LEAVES_VHOST:-}" ]]; then
  assert_cmd "it answers through the host nginx, not just on 8081" \
    curl -fsS -o /dev/null --max-time 10 -H "Host: ${LEAVES_VHOST}" \
    "http://127.0.0.1/etoile-formation-conge/"
else
  printf 'SKIP  LEAVES_VHOST is not set, so the proxy path was not checked\n'
fi

# The end state that matters: the fix lives where the service manager can find
# it, so a restart brings the app back unaided.
svc_restart leaves web >/dev/null 2>&1 || true
assert_eventually "it is running again after a full restart" 60 \
  svc_is_active leaves web
assert_eventually "it answers again after a full restart" 30 \
  curl -fsS -o /dev/null --max-time 5 "$url"

assert_summary
