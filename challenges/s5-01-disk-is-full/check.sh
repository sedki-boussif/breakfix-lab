#!/usr/bin/env bash
# s5-01 — check: the filesystem has room AND the file that filled it is gone.
# Usage under 80% on its own would pass for someone who deleted the logs.
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

mnt="$(lab_fs_mnt uploads)"
control="$mnt/.lab-absence-control"

if ! mountpoint -q "$mnt" 2>/dev/null; then
  printf 'The uploads filesystem is not mounted at %s.\n' "$mnt" >&2
  printf 'Run: lab reset s5-01-disk-is-full  (or lab start, to begin it)\n' >&2
  exit 1
fi

# A measurement, read directly: no control needed.
assert_below "the uploads filesystem has room" "$(lab_fs_pct "$mnt")" 80 "%"

# An absence claim, so the detector is proved first. The control is sparse:
# 128 MB of apparent size and no blocks, so it costs nothing on a full volume.
detect_big() { [[ -n "$(lab_as_root find "$mnt" -xdev -type f -size +64M -print -quit 2>/dev/null)" ]]; }
plant_big()  { lab_as_root truncate -s 128M "$control"; }
clean_big()  { lab_as_root rm -f "$control"; }
assert_absent "the file that filled the volume is gone" detect_big plant_big clean_big

# Nothing else was broken in the process.
assert_http "stages still answers" "${STAGES_URL:?}" 200
assert_http "leaves still answers" "${LEAVES_URL:?}" 200
assert_http "the theses API still answers" "${NURSE_API:?}" 200

assert_summary
