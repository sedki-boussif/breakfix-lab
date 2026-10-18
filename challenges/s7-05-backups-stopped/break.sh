#!/usr/bin/env bash
# s7-05 — break: the backup timer is disabled, and the success marker is
# backdated to look recent so the dead-man's-switch stays quiet.
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

# Record the real state once, so reset restores rather than guesses.
if [[ -z "$(lab_state_get "$ID" WAS_ENABLED '')" ]]; then
  lab_state_set "$ID" WAS_ENABLED "$(systemctl is-enabled "$timer" 2>/dev/null || echo unknown)"
  if [[ -e "$marker" ]]; then
    lab_state_set "$ID" MARKER_MTIME "$(stat -c '%Y' "$marker")"
  fi
fi

lab_as_root systemctl disable --now "$timer" >/dev/null 2>&1 || true

# The marker looks fresh, which is why nothing has complained. This is the
# fault that turns a one-day problem into a three-week one.
lab_as_root mkdir -p "$(dirname "$marker")"
lab_as_root touch -d '2 hours ago' "$marker"

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
