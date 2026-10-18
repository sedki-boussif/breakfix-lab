#!/usr/bin/env bash
# s4-06 — reset: put the listener back on the original port. Only possible
# while you still have a session, or from the console.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-06-locked-out-of-ssh'
dropin="$(lab_state_get "$ID" DROPIN '/etc/systemd/system/ssh.socket.d/90-lab.conf')"
old="$(lab_state_get "$ID" OLD_PORT "${SSH_PORT:-22}")"

lab_as_root rm -f "$dropin"
lab_restore_file "$ID" /etc/ssh/sshd_config
lab_as_root systemctl daemon-reload >/dev/null 2>&1 || true
lab_as_root systemctl restart ssh.socket >/dev/null 2>&1 || true
lab_as_root ufw allow "${old}/tcp" >/dev/null 2>&1 || true
printf 'SSH is back on port %s. Confirm with a NEW session before closing this one.\n' "$old"
lab_state_set "$ID" BROKEN_AT 0
