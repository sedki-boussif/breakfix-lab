#!/usr/bin/env bash
# s5-02 — break: exhaust the inodes on a small, inode-starved filesystem. Bytes
# stay almost entirely free, which is the point.
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

ID='s5-02-space-but-writes-fail'
mnt="$(lab_fs_require spool "${S5_SPOOL_MB:-64}" "${S5_SPOOL_INODES:-2048}")"
lab_fs_is_ours "$mnt" || { printf 'refusing: %s is not a lab filesystem\n' "$mnt" >&2; exit 1; }
spool="$mnt/incoming/.partial"

# Idempotent: already exhausted means nothing left to do.
if [[ "$(lab_fs_inode_pct "$mnt")" -lt 95 ]]; then
  lab_as_root mkdir -p "$spool"
  # One inode each, no bytes. Stops on its own when the table is full.
# Values are passed as positional parameters rather than interpolated
# into the script text: safer, and $1/$2 below are deliberate.
# shellcheck disable=SC2016
  lab_as_root bash -c '
    cd "$1" || exit 0
    for i in $(seq 1 100000); do
      : >"spool-$i.tmp" 2>/dev/null || exit 0
    done' _ "$spool"
fi

lab_state_set "$ID" MNT "$mnt"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
