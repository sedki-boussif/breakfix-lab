#!/usr/bin/env bash
# s5-03 — reset: stop the holder and reformat the volume.
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

ID='s5-03-deleted-file-held-open'
pidfile="$(lab_state_dir "$ID")/holder.pid"

if [[ -f "$pidfile" ]]; then
  pid="$(cat "$pidfile")"
  [[ -z "$pid" ]] || lab_as_root kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
fi
lab_fs_reformat logs "${S5_LOGS_MB:-512}" >/dev/null
lab_state_set "$ID" BROKEN_AT 0
