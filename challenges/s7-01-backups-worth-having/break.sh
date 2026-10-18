#!/usr/bin/env bash
# s7-01 — a mission: nothing is broken. This prepares the off-site filesystem
# and the directories the standard refers to, so that "put it somewhere else"
# means somewhere that exists.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"

ID='s7-01-backups-worth-having'

# The off-site location is a filesystem of its own, so that a full local disk
# cannot take the backups with it. Bounded, like everything else here.
mnt="$(lab_fs_require offsite "${BACKUP_REMOTE_MB:-1024}")"
lab_fs_is_ours "$mnt" || { printf 'refusing: %s is not a lab filesystem\n' "$mnt" >&2; exit 1; }

lab_as_root mkdir -p "$(dirname "${BACKUP_REPO:?}")" \
                     "$(dirname "${BACKUP_PASSWORD_FILE:?}")" \
                     "$(dirname "${BACKUP_ALERT_LOG:?}")"
lab_as_root touch "${BACKUP_ALERT_LOG}"

printf 'Nothing is broken: this is a mission.\n'
printf 'The off-site filesystem is mounted at %s.\n' "$mnt"
printf 'Build the backup system to the standard in the brief, then: lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
