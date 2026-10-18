#!/usr/bin/env bash
# s6-01 — check, in two phases: the only honest test of a mount is a reboot.
#
#   check.sh --arm   after building the stack and moving the data
#   (then extend the volume, and reboot)
#   check.sh         asserts it came back, by UUID, and grew
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

ID='s6-01-give-docker-its-own-volume'
target='/var/lib/docker'
state="$(lab_state_dir "$ID")"
armed="$state/armed"
sizefile="$state/lv-size"
report="$LAB_ROOT/reports/${ID}.md"
boot_id="$(cat /proc/sys/kernel/random/boot_id)"

lv_size_kb() {
  local dev; dev="$(findmnt -n -o SOURCE --target "$target" 2>/dev/null || true)"
  [[ -n "$dev" ]] || return 1
  lab_as_root lvs --noheadings --units k --nosuffix -o LV_SIZE "$dev" 2>/dev/null | tr -d ' '
}

if [[ "${1:-}" == "--arm" ]]; then
  if ! mountpoint -q "$target"; then
    printf '%s is not a separate mount yet. Build the stack and move the data first.\n' "$target" >&2
    exit 1
  fi
  sz="$(lv_size_kb || true)"
  if [[ -z "$sz" ]]; then
    printf '%s is a mount but not on an LVM logical volume — lvs does not know it.\n' "$target" >&2
    printf 'The mission is specifically LVM, because the extend in step 5 needs it.\n' >&2
    exit 1
  fi
  printf '%s\n' "$boot_id" >"$armed"
  printf '%s\n' "$sz" >"$sizefile"
  printf 'Armed. Logical volume is %s kB now.\n' "$sz"
  printf 'Extend it live, with the apps serving, then reboot, then: lab check %s\n' "$ID"
  exit 0
fi

if [[ ! -f "$armed" ]]; then
  printf 'Not armed yet. This mission is proved in two phases:\n'
  printf '  lab check %s --arm      (after building and moving)\n' "$ID"
  printf '  ...extend the volume, then reboot...\n'
  printf '  lab check %s\n' "$ID"
  exit 1
fi

if [[ "$(cat "$armed")" == "$boot_id" ]]; then
  assert_fail "the VM has rebooted since arming" \
    "the boot id has not changed — a mount that has not survived a boot is not proven"
  assert_summary
  exit $?
fi
assert_pass "the VM has rebooted since arming"

# A mount of its own, on LVM, after the reboot — unaided.
assert_cmd "${target} is a separate mount" mountpoint -q "$target"
src="$(findmnt -n -o SOURCE --target "$target" 2>/dev/null || true)"
if [[ -n "$src" ]] && lab_as_root lvs "$src" >/dev/null 2>&1; then
  assert_pass "${target} is on an LVM logical volume (${src})"
else
  assert_fail "${target} is on an LVM logical volume" "it is on '${src:-nothing}'"
fi

# By UUID, not by device name.
fstab_line="$(grep -vE '^\s*#' /etc/fstab | grep -F " ${target} " || true)"
if [[ -z "$fstab_line" ]]; then
  assert_fail "/etc/fstab mounts ${target}" \
    "it is mounted now but not in fstab, so the next boot loses it"
elif grep -qE '^\s*UUID=' <<<"$fstab_line"; then
  assert_pass "/etc/fstab mounts it by UUID"
else
  assert_fail "/etc/fstab mounts it by UUID" \
    "the entry is '${fstab_line}' — a device name moves when the hypervisor reorders disks, and then the machine does not boot"
fi
assert_cmd "mount -a is clean" lab_as_root mount -a

# It grew.
was="$(cat "$sizefile" 2>/dev/null || echo 0)"
now="$(lv_size_kb || echo 0)"
assert_above "the logical volume is larger than when armed (${was} kB)" "$now" "$was" " kB"

# Docker and the applications came back with it.
assert_cmd "docker is running" systemctl is-active --quiet docker
assert_cmd "docker still has its images" \
  bash -c 'lab_as_root docker images --format "{{.Repository}}" | grep -q .'
assert_http "stages answers" "${STAGES_URL:?}" 200
assert_http "leaves answers" "${LEAVES_URL:?}" 200
assert_http "the theses API answers" "${NURSE_API:?}" 200

# And the claim that nothing went down during the extend, which only the
# person who did it can attest to.
if [[ -f "$report" ]]; then
  assert_file_matches "the report records that the apps stayed up during the extend" \
    "$report" '[Ss]tayed up|no downtime|during the extend|kept serving|200'
  assert_file_matches "the report records the size before and after" \
    "$report" '[0-9]+(\.[0-9]+)? ?(G|M|k)'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the live extend is the part worth writing down"
fi

rm -f "$armed"
assert_summary
