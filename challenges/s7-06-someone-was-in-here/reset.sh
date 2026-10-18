#!/usr/bin/env bash
# s7-06 — reset: remove all four traces, in the order that works.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-06-someone-was-in-here'
user="$(lab_state_get "$ID" USER "${INTRUDER_USER:-svc-backup}")"
cron_file="$(lab_state_get "$ID" CRON "/etc/cron.d/lab-${user}-sync")"
pidfile="$(lab_state_dir "$ID")/listener.pid"

# Persistence first, or it undoes the rest.
lab_as_root rm -f "$cron_file"
if [[ -f "$pidfile" ]]; then
  pid="$(cat "$pidfile")"
  [[ -z "$pid" ]] || lab_as_root kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
fi
lab_as_root pkill -f 'kworker/u8:2-events' 2>/dev/null || true
if [[ "$(lab_state_get "$ID" CREATED_USER 0)" == 1 ]] && id -u "$user" >/dev/null 2>&1; then
  lab_as_root userdel -r "$user" >/dev/null 2>&1 || true
  lab_state_set "$ID" CREATED_USER 0
fi
lab_state_set "$ID" BROKEN_AT 0
