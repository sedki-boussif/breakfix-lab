#!/usr/bin/env bash
# s7-06 — break: plant four traces of an intrusion that reinforce each other,
# so that cleaning up in the obvious order does not hold.
#
# Nothing here touches your account, your keys, or sshd's configuration.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-06-someone-was-in-here'
user="${INTRUDER_USER:-svc-backup}"
port="${INTRUDER_PORT:-47113}"
cron_file="/etc/cron.d/lab-${user}-sync"
keyfile="/home/${user}/.ssh/authorized_keys"
pidfile="$(lab_state_dir "$ID")/listener.pid"

# A throwaway key with an obviously invented comment. Generated, never shipped.
key="$(lab_state_dir "$ID")/intruder.key"
if [[ ! -f "$key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'sync@maintenance-node' -f "$key" </dev/null
fi
pub="$(cut -d' ' -f1-2 "${key}.pub") sync@maintenance-node"

# 1. The account: locked password, no sudo, but a real login shell.
if ! id -u "$user" >/dev/null 2>&1; then
  lab_as_root useradd --create-home --shell /bin/bash --password '!' "$user"
  lab_state_set "$ID" CREATED_USER 1
fi

# 2. The key, in the planted account's own authorized_keys.
lab_as_root install -d -m 700 -o "$user" -g "$user" "/home/${user}/.ssh"
printf '%s\n' "$pub" | lab_as_root tee "$keyfile" >/dev/null
lab_as_root chown "$user:$user" "$keyfile"
lab_as_root chmod 600 "$keyfile"

# 3. The persistence: a cron job that puts the key back every two minutes.
#    This is why removing the key alone achieves nothing.
lab_as_root tee "$cron_file" >/dev/null <<CRON
# Node synchronisation helper
SHELL=/bin/sh
PATH=/usr/bin:/bin
*/2 * * * * root mkdir -p /home/${user}/.ssh && grep -qxF '${pub}' ${keyfile} 2>/dev/null || echo '${pub}' >> ${keyfile}
CRON
lab_as_root chmod 644 "$cron_file"

# 4. Something listening, under a name that looks like it belongs.
if [[ ! -f "$pidfile" ]] || ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  # shellcheck disable=SC2016  # $1 and $2 are the inner script's parameters
  lab_as_root bash -c '
    echo $$ >"$2"
    exec -a "[kworker/u8:2-events]" python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((\"127.0.0.1\", int(\"$1\"))); s.listen(1)
while True: time.sleep(3600)
"' _ "$port" "$pidfile" &
  sleep 2
fi

lab_state_set "$ID" USER "$user"
lab_state_set "$ID" PORT "$port"
lab_state_set "$ID" CRON "$cron_file"
lab_state_set "$ID" KEYFILE "$keyfile"
lab_state_set "$ID" PUBKEY "$pub"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
