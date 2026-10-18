#!/usr/bin/env bash
# s9-03 — reset: stop the writer and reformat the filesystem.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"

ID='s9-03-worse-over-hours'
pidfile="$(lab_state_dir "$ID")/writer.pid"

if [[ -f "$pidfile" ]]; then
  pid="$(cat "$pidfile")"
  [[ -z "$pid" ]] || lab_as_root pkill -P "$pid" 2>/dev/null || true
  [[ -z "$pid" ]] || lab_as_root kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
fi
lab_as_root pkill -f 'leaves-debug-writer' 2>/dev/null || true
sleep 1
lab_fs_reformat growth "${S9_03_MB:-512}" >/dev/null
lab_state_set "$ID" BROKEN_AT 0
