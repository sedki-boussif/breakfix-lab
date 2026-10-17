#!/usr/bin/env bash
# s5-01 — reset: reformat the filesystem, which is O(1) rather than a traversal.
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
lab_fs_reformat uploads "${S5_UPLOADS_MB:-512}" >/dev/null
lab_state_set "$ID" BROKEN_AT 0
