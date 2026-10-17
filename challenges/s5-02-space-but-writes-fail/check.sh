#!/usr/bin/env bash
# s5-02 — check: inodes are available, a write actually succeeds, and the files
# that consumed them are gone.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

mnt="$(lab_fs_mnt spool)"
control="$mnt/.lab-absence-control"

if ! mountpoint -q "$mnt" 2>/dev/null; then
  printf 'The spool filesystem is not mounted at %s.\n' "$mnt" >&2
  printf 'Run: lab reset s5-02-space-but-writes-fail\n' >&2
  exit 1
fi

assert_below "inodes are available on the spool filesystem" \
  "$(lab_fs_inode_pct "$mnt")" 80 "%"

# The end state the clerk cares about: a write succeeds.
assert_cmd "a write to the spool filesystem succeeds" \
  lab_as_root install -m 644 /dev/null "$mnt/.lab-write-probe"
lab_as_root rm -f "$mnt/.lab-write-probe"

# Absence, with the detector proved against a planted batch first.
detect_many() { [[ "$(lab_as_root find "$mnt" -xdev -type f -name '*.tmp' -printf . 2>/dev/null | wc -c)" -ge 200 ]]; }
# Values are passed as positional parameters rather than interpolated
# into the script text: safer, and $1/$2 below are deliberate.
# shellcheck disable=SC2016
plant_many()  { lab_as_root mkdir -p "$control" && lab_as_root bash -c 'cd "$1" && for i in $(seq 1 250); do : >"ctl-$i.tmp"; done' _ "$control"; }
clean_many()  { lab_as_root rm -rf "$control"; }
assert_absent "the files that consumed the inodes are gone" detect_many plant_many clean_many

assert_summary
