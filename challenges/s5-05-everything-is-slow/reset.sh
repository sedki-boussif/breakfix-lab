#!/usr/bin/env bash
# s5-05 — reset: stop the loops. Harmless twice.
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

ID='s5-05-everything-is-slow'
pidfile="$(lab_state_dir "$ID")/spinners.pids"

if [[ -f "$pidfile" ]]; then
  while read -r pid; do
    [[ -z "$pid" ]] || lab_as_root kill "$pid" 2>/dev/null || true
  done <"$pidfile"
  rm -f "$pidfile"
fi
lab_as_root pkill -f "${S5_SPIN_NAME:-apt-cache-gen}" 2>/dev/null || true
lab_state_set "$ID" BROKEN_AT 0
