#!/usr/bin/env bash
# s7-04 — reset: nothing to undo, but removing immutability is how you get your
# repository back under your own control if you want to start over.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

printf 'Nothing to undo: s7-04 is a mission.\n'
printf 'If you need to unwind what you built — note that this is exactly the\n'
printf 'command an attacker would need, which is the point of the mission:\n'
printf '  sudo chattr -R -i -a %s   # if you used file attributes\n' "${BACKUP_REMOTE:-/srv/lab-offsite/repo}"
printf '  sudo chown -R %s %s   # if you used a separate owner\n' \
  "$(id -un)" "${BACKUP_REMOTE:-/srv/lab-offsite/repo}"
lab_state_set 's7-04-append-only-backups' BROKEN_AT 0
