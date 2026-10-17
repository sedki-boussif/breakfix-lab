#!/usr/bin/env bash
# s5-07 — reset: restore the fstab. Only useful BEFORE the reboot; afterwards
# the machine is in emergency mode and there is no lab to run this from.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s5-07-boots-to-emergency'
fstab="${FSTAB:-/etc/fstab}"

lab_restore_file "$ID" "$fstab"
# If no backup existed, at least remove our own appended line.
if grep -qF '# lab s5-07' "$fstab" 2>/dev/null; then
  lab_as_root sed -i '/# lab s5-07/d' "$fstab"
fi
lab_as_root systemctl daemon-reload >/dev/null 2>&1 || true
lab_as_root mount -a 2>&1 | sed 's/^/mount -a: /' || true
rm -f "$(lab_state_dir "$ID")/armed"
lab_state_set "$ID" BROKEN_AT 0
