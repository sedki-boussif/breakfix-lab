#!/usr/bin/env bash
# s4-06 — break: move the SSH listener with a socket drop-in and leave the
# firewall pointed at the old port. Existing sessions survive; new ones cannot
# connect on either port.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-06-locked-out-of-ssh'
old="${SSH_PORT:-22}"
new="${S4_06_NEW_PORT:-2222}"
dropin_dir='/etc/systemd/system/ssh.socket.d'
dropin="${dropin_dir}/90-lab.conf"

lab_require_confirm 'yes-i-have-console' \
  "$(cat <<'TXT'
This removes your SSH access to this machine. Your CURRENT session survives;
no new session will be able to connect on either the old or the new port.

reset.sh can undo it only while you still have that session. After that,
recovery is the hypervisor console, or rolling back the snapshot.

You need, before continuing:
  - a snapshot of this VM
  - the hypervisor console OPEN AND LOGGED IN, checked just now
TXT
)"

# The socket drop-in: this is what actually decides the port on 24.04.
lab_as_root mkdir -p "$dropin_dir"
printf '[Socket]\nListenStream=\nListenStream=%s\n' "$new" | lab_as_root tee "$dropin" >/dev/null
lab_state_set "$ID" DROPIN "$dropin"

# And the half-finished part: sshd_config is edited too, which is where
# everyone will look and which changes nothing by itself.
lab_backup_file "$ID" /etc/ssh/sshd_config
if grep -qE '^#?Port ' /etc/ssh/sshd_config; then
  lab_as_root sed -i -E "s/^#?Port .*/Port ${new}/" /etc/ssh/sshd_config
else
  printf 'Port %s\n' "$new" | lab_as_root tee -a /etc/ssh/sshd_config >/dev/null
fi

lab_as_root systemctl daemon-reload >/dev/null 2>&1 || true
lab_as_root systemctl restart ssh.socket >/dev/null 2>&1 || true

# The firewall still allows only the old port, so the new one is unreachable.
lab_state_set "$ID" OLD_PORT "$old"
lab_state_set "$ID" NEW_PORT "$new"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"

printf '\nDone. Your current session is still alive; new connections are not possible.\n'
printf 'Recover at the console. Do not close this session until you have.\n'
