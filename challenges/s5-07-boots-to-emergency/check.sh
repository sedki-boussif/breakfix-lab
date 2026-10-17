#!/usr/bin/env bash
# s5-07 — check, in two phases: the only honest test of "it boots" is a boot.
#
#   check.sh --arm   record the boot id, then reboot
#   check.sh         assert it came up unaided, with every mount present
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s5-07-boots-to-emergency'
fstab="${FSTAB:-/etc/fstab}"
armed="$(lab_state_dir "$ID")/armed"
ctl_unit='/run/systemd/system/lab-absence-control.mount'
boot_id="$(cat /proc/sys/kernel/random/boot_id)"

if [[ "${1:-}" == "--arm" ]]; then
  printf '%s\n' "$boot_id" >"$armed"
  printf 'Armed. Now reboot the VM with sudo reboot.\n'
  printf 'It will not come back on its own: recover at the console, then run\n'
  printf '  lab check %s\n' "$ID"
  exit 0
fi

if [[ ! -f "$armed" ]]; then
  printf 'Not armed yet. This challenge is proved across a reboot:\n'
  printf '  lab check %s --arm\n  sudo reboot\n  (recover at the console)\n  lab check %s\n' "$ID" "$ID"
  exit 1
fi

if [[ "$(cat "$armed")" == "$boot_id" ]]; then
  assert_fail "the VM has rebooted since arming" \
    "the boot id has not changed — this has to be run after the reboot"
  assert_summary
  exit $?
fi
assert_pass "the VM has rebooted since arming"

# It reached a working multi-user system without being nursed through it.
assert_cmd "the boot reached its default target, not emergency mode" \
  systemctl is-active --quiet default.target
assert_not "the system is not in emergency or rescue mode" \
  systemctl is-active --quiet emergency.target

# Every entry in fstab is actually mounted, so a line commented out for a device
# that is still expected does not pass as a fix.
assert_cmd "mount -a is clean: every fstab entry mounts" lab_as_root mount -a

# Absence, with the detector proved against a mount unit planted to fail.
detect_failed_mount() {
  local n
  n="$(systemctl list-units --type=mount --state=failed --no-legend --plain 2>/dev/null | grep -c . || true)"
  (( n > 0 ))
}
plant_failed_mount() {
  lab_as_root mkdir -p /run/lab-absence-control
  printf '[Unit]\nDescription=lab absence control\n[Mount]\nWhat=/dev/disk/by-uuid/99999999-8888-7777-6666-555555555555\nWhere=/run/lab-absence-control\nType=ext4\n' |
    lab_as_root tee "$ctl_unit" >/dev/null
  lab_as_root systemctl daemon-reload
  lab_as_root systemctl start lab-absence-control.mount >/dev/null 2>&1 || true
  sleep 2
}
clean_failed_mount() {
  lab_as_root systemctl stop lab-absence-control.mount >/dev/null 2>&1 || true
  lab_as_root systemctl reset-failed lab-absence-control.mount >/dev/null 2>&1 || true
  lab_as_root rm -f "$ctl_unit"
  lab_as_root rmdir /run/lab-absence-control 2>/dev/null || true
  lab_as_root systemctl daemon-reload
  sleep 1
}
assert_absent "no mount unit is in a failed state" \
  detect_failed_mount plant_failed_mount clean_failed_mount

# The fstab no longer names a device that does not exist.
if grep -qE '^[^#]*UUID=11111111-2222-3333-4444-555555555555' "$fstab" 2>/dev/null; then
  assert_fail "no fstab entry names a device that is not there" \
    "the bogus UUID is still active in ${fstab}"
else
  assert_pass "no fstab entry names a device that is not there"
fi

assert_http "stages answers again" "${STAGES_URL:?}" 200
assert_http "leaves answers again" "${LEAVES_URL:?}" 200
assert_http "the theses API answers again" "${NURSE_API:?}" 200

rm -f "$armed"
assert_summary
