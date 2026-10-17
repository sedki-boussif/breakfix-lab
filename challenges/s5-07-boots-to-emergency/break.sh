#!/usr/bin/env bash
# s5-07 — break: append an fstab entry for a UUID that does not exist, so the
# next boot stops in emergency mode.
#
# This cannot be undone once the machine has rebooted. It asks first.
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
marker='# lab s5-07'
mnt="${LAB_SCRATCH_MNT:-/srv/lab-scratch}/archive"
# Fixed and obviously invented, so it can never match a real device.
bogus='11111111-2222-3333-4444-555555555555'

lab_require_confirm 'yes-i-have-a-snapshot-and-console' \
  "$(cat <<'TXT'
This break stops the VM from booting. reset.sh cannot undo it once you reboot:
recovery is through the hypervisor console, or by rolling back the snapshot.

You need, before continuing:
  - a snapshot of this VM that you can roll back to
  - the hypervisor console open, because SSH will not come back
TXT
)"

[[ -f "$fstab" ]] || { printf 'no fstab at %s\n' "$fstab" >&2; exit 1; }
lab_backup_file "$ID" "$fstab"

# Idempotent: one entry, appended, never editing a line that was already there.
if ! grep -qF "$marker" "$fstab"; then
  lab_as_root mkdir -p "$mnt"
  printf 'UUID=%s %s ext4 defaults 0 2 %s\n' "$bogus" "$mnt" "$marker" |
    lab_as_root tee -a "$fstab" >/dev/null
fi
lab_as_root systemctl daemon-reload >/dev/null 2>&1 || true

lab_state_set "$ID" FSTAB "$fstab"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"

printf '\nDone. The running system is unaffected: the fault is in the boot path.\n'
printf 'Arm the check, then reboot:\n'
printf '  lab check %s --arm\n  sudo reboot\n' "$ID"
