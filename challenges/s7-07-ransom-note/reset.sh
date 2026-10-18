#!/usr/bin/env bash
# s7-07 — reset: restores the lab's own state — the local repository, and a
# clean uploads directory. It CANNOT restore the uploaded files: nothing kept
# them, which is the point of the challenge. Use the off-site copy, or the
# snapshot.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-07-ransom-note'
path="$(lab_state_get "$ID" PATH_ '')"
arch="$(lab_state_get "$ID" LOCAL_ARCHIVE '')"

if [[ -n "$arch" && -f "$arch" ]]; then
  lab_as_root mkdir -p "${BACKUP_REPO:?}"
  lab_as_root tar -xf "$arch" -C "${BACKUP_REPO}"
fi
if [[ -n "$path" && -d "$path" ]]; then
  lab_as_root rm -f "${path}"/*.locked "${path}/READ_ME_TO_RECOVER.txt" 2>/dev/null || true
fi
printf 'The local repository and a clean uploads directory are back.\n'
printf 'The uploaded FILES are not: restore them from the off-site copy, or roll\n'
printf 'back the snapshot. That asymmetry is the whole lesson of this challenge.\n'
lab_state_set "$ID" BROKEN_AT 0
