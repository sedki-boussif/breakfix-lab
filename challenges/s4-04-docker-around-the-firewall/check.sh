#!/usr/bin/env bash
# s4-04 — check: the denied port is genuinely unreachable from the LAN address,
# and the application still works through nginx. Loopback is not the test.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s4-04-docker-around-the-firewall'
ip="${LAB_LAN_IP:?set LAB_LAN_IP in lab.conf — this mission is meaningless without it}"
port="${S4_04_PORT:-9090}"
report="$LAB_ROOT/reports/${ID}.md"

# The assertion that matters: not reachable from the LAN address.
assert_not "port ${port} is unreachable at ${ip} (the LAN address)" \
  curl -fsS -o /dev/null --max-time 6 "http://${ip}:${port}/"

# Nothing is published on all interfaces that should not be.
published_wide="$(lab_as_root docker ps --format '{{.Ports}}' 2>/dev/null \
                  | tr ',' '\n' | grep -E '^[[:space:]]*0\.0\.0\.0:' || true)"
if [[ -z "$published_wide" ]]; then
  assert_pass "no container publishes a port on all interfaces"
else
  assert_fail "no container publishes a port on all interfaces" \
    "still published wide: $(tr '\n' ' ' <<<"$published_wide")— prefix the host port with 127.0.0.1:"
fi

# The DOCKER-USER chain has been understood, one way or the other: either the
# port is not published at all, or there is a rule in the chain that governs
# container traffic.
if lab_as_root iptables -S DOCKER-USER 2>/dev/null | grep -qE -- '-j (DROP|REJECT)'; then
  assert_pass "DOCKER-USER carries a filtering rule"
else
  printf 'SKIP  no DOCKER-USER rule found — acceptable if you fixed it by binding to loopback\n'
fi

# And the application still works, through the proxy, which is the half that
# makes this a fix rather than an outage.
assert_http "stages still answers through its own port" "${STAGES_URL:?}" 200
if [[ -n "${STAGES_VHOST:-}" ]]; then
  assert_cmd "stages answers through the host nginx" \
    curl -fsS -o /dev/null --max-time 10 -H "Host: ${STAGES_VHOST}" "http://127.0.0.1/"
fi

# The firewall is still a firewall.
assert_cmd "ufw is enabled" \
  bash -c 'ufw status 2>/dev/null | grep -qE "Status:[[:space:]]*active"'

# The mechanism, written down, because that is what transfers.
if [[ -f "$report" ]]; then
  assert_file_matches "the report explains why ufw was bypassed" \
    "$report" 'DOCKER-USER|FORWARD|forward|nat table|ufw-input'
  assert_file_matches "the report says how the rule survives a reboot" \
    "$report" 'persist|reboot|iptables-save|systemd unit|after.rules'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the mechanism is the lesson, not the commands"
fi

assert_summary
