#!/usr/bin/env bash
# s7-01 — reset: a mission has nothing to undo. This removes only the
# scaffolding break.sh created, and deliberately leaves your work alone.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

printf 'Nothing to undo: s7-01 is a mission and your backup system is yours.\n'
printf 'To start over, remove what you built:\n'
printf '  sudo systemctl disable --now %s\n' "${BACKUP_TIMER:-lab-backup.timer}"
printf '  sudo rm -rf %s %s\n' "${BACKUP_REPO:-/var/backups/lab/repo}" "${BACKUP_REMOTE:-/srv/lab-offsite/repo}"
printf '  and lib/fs.sh lab_fs_destroy offsite  to remove the off-site filesystem\n'
lab_state_set 's7-01-backups-worth-having' BROKEN_AT 0
