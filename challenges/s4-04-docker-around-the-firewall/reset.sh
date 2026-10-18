#!/usr/bin/env bash
# s4-04 — reset: remove the demonstration's leftovers, if you want to start over.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

port="${S4_04_PORT:-9090}"
printf 'Nothing to undo: s4-04 is a mission. To clear the demonstration:\n'
printf '  sudo ufw delete deny %s/tcp\n' "$port"
printf '  sudo iptables -D DOCKER-USER -p tcp --dport %s -j DROP   # if you added it\n' "$port"
printf '  remove the ports: entry you added, then: cd %s && docker compose up -d\n' "${STAGES_DIR:-/opt/stages}"
lab_state_set 's4-04-docker-around-the-firewall' BROKEN_AT 0
