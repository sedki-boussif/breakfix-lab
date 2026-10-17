#!/usr/bin/env bash
# s5-01 — break: fill a bounded filesystem with one large file in a place the
# usual du invocation cannot see.
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

ID='s5-01-disk-is-full'
mnt="$(lab_fs_require uploads "${S5_UPLOADS_MB:-512}")"
# Checked again here, independently of the library: this script is about to
# write a large file, and it may only ever do that on a bounded lab filesystem.
lab_fs_is_ours "$mnt" || { printf 'refusing: %s is not a lab filesystem\n' "$mnt" >&2; exit 1; }
spool="$mnt/.cache/.import-spool"
target="$spool/.spool-20261016.dat"

# Idempotent: if it is already full, leave it exactly as it is.
if [[ "$(lab_fs_pct "$mnt")" -lt 90 ]]; then
  lab_as_root mkdir -p "$spool"
  # Take it to about 96%, leaving room to recover without a reformat.
  # 95% of what is free, hard-capped by the filesystem's configured size.
  fill_k="$(lab_fs_fill_kb "$mnt" 95 "${S5_UPLOADS_MB:-512}")"
  lab_as_root fallocate -l "${fill_k}K" "$target" 2>/dev/null ||
    lab_as_root dd if=/dev/zero of="$target" bs=1K count="$fill_k" status=none
  lab_as_root touch -d '2026-10-16 03:14' "$target"
fi

lab_state_set "$ID" MNT "$mnt"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
