#!/usr/bin/env bash
# s7-03 — reset: put both repositories back from the copies taken before the
# break, and re-seed the emptied tables.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-03-the-backups-are-gone'
arch="$(lab_state_get "$ID" ARCHIVE '')"
larch="$(lab_state_get "$ID" LOCAL_ARCHIVE '')"

if [[ -n "$arch" && -f "$arch" ]]; then
  lab_as_root rm -rf "${BACKUP_REMOTE:?}"
  lab_as_root mkdir -p "${BACKUP_REMOTE}"
  lab_as_root tar -xf "$arch" -C "${BACKUP_REMOTE}"
fi
if [[ -n "$larch" && -f "$larch" ]]; then
  lab_as_root mkdir -p "${BACKUP_REPO:?}"
  lab_as_root tar -xf "$larch" -C "${BACKUP_REPO}"
fi
bash "$LAB_ROOT/lib/seed.sh" stages >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
