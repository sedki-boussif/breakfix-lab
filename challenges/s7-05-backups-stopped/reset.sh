#!/usr/bin/env bash
# s7-05 — reset: re-enable the timer and put the marker's timestamp back.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-05-backups-stopped'
timer="${BACKUP_TIMER:?}"
marker="${BACKUP_MARKER:?}"
was="$(lab_state_get "$ID" WAS_ENABLED '')"
mtime="$(lab_state_get "$ID" MARKER_MTIME '')"

if [[ "$was" == "enabled" || "$was" == "unknown" ]]; then
  lab_as_root systemctl enable --now "$timer" >/dev/null 2>&1 || true
fi
[[ -z "$mtime" ]] || lab_as_root touch -d "@${mtime}" "$marker" 2>/dev/null || true
lab_state_set "$ID" BROKEN_AT 0
