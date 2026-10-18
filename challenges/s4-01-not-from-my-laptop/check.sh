#!/usr/bin/env bash
# s4-01 — check: reachable from the VM's own LAN address, with the firewall
# still doing its job. Loopback is deliberately not the test.
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

ip="${LAB_LAN_IP:-}"
vhost="${LEAVES_VHOST:-conge.lab.invalid}"

if [[ -z "$ip" ]]; then
  printf 'LAB_LAN_IP is not set in lab.conf, and this challenge is entirely about\n' >&2
  printf 'reaching the VM the way your laptop does. Set it (SETUP.md section 4).\n' >&2
  exit 1
fi

# The test that matters: the LAN address, not loopback.
assert_cmd "the app answers on the VM's LAN address (${ip})" \
  curl -fsS -o /dev/null --max-time 10 -H "Host: ${vhost}" "http://${ip}/etoile-formation-conge/"

# And loopback still works, which proves the fix did not involve breaking it.
assert_http "it still answers on loopback too" "${LEAVES_URL:?}" 200

# The firewall is still a firewall.
status="$(lab_as_root ufw status verbose 2>/dev/null || true)"
if grep -qE 'Status:[[:space:]]*active' <<<"$status"; then
  assert_pass "ufw is enabled"
else
  assert_fail "ufw is enabled" \
    "turning the firewall off makes the symptom go away and is a worse incident"
fi
if grep -qE 'Default:.*deny \(incoming\)' <<<"$status"; then
  assert_pass "the default inbound policy is deny"
else
  assert_fail "the default inbound policy is deny" \
    "sudo ufw default deny incoming   # then re-allow only what EXPECTED_PORTS lists"
fi

# No deny rule left shadowing the thing it is supposed to allow.
if grep -qiE '^(80|443)/tcp[[:space:]]+DENY' <<<"$status"; then
  assert_fail "no deny rule shadows the web ports" \
    "ufw is first-match: sudo ufw status numbered, then delete the DENY that precedes the ALLOW"
else
  assert_pass "no deny rule shadows the web ports"
fi

# The allowed set matches what the lab expects, rather than everything.
if [[ -n "${EXPECTED_PORTS:-}" ]]; then
  extra=""
  while read -r p; do
    [[ -n "$p" ]] || continue
    if [[ " ${EXPECTED_PORTS} " != *" ${p} "* ]]; then extra+="${p} "; fi
  done < <(grep -oE '^[0-9]+' <<<"$status" | sort -un)
  if [[ -z "$extra" ]]; then
    assert_pass "ufw allows only expected ports"
  else
    assert_fail "ufw allows only expected ports" "also allowed: ${extra}"
  fi
else
  printf 'SKIP  EXPECTED_PORTS is not set, so the allow list was not checked\n'
fi

assert_summary
