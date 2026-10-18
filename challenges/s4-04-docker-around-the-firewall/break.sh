#!/usr/bin/env bash
# s4-04 — a mission: nothing is broken. This records the LAN address the check
# will test from, and refuses early if there is no way to test honestly.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-04-docker-around-the-firewall'

if [[ -z "${LAB_LAN_IP:-}" ]]; then
  printf 'LAB_LAN_IP is not set in lab.conf.\n' >&2
  printf 'This whole mission is about what is reachable from ANOTHER machine, so\n' >&2
  printf 'it cannot be done or checked without it. SETUP.md section 4.\n' >&2
  exit 1
fi

printf 'Nothing is broken: this is a mission.\n'
printf 'Part one is a demonstration — publish port %s, deny it in ufw, and reach\n' "${S4_04_PORT:-9090}"
printf 'it from your laptop at http://%s:%s/\n' "$LAB_LAN_IP" "${S4_04_PORT:-9090}"
printf '\nThen fix it twice, and: lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
