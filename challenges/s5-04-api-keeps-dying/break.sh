#!/usr/bin/env bash
# s5-04 — break: the API's own cgroup gets a memory limit far below what it
# needs, so the cgroup OOM killer kills the API and only the API. A bounded
# memory hog makes the box feel slow and is not the cause.
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
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s5-04-api-keeps-dying'
hog_name="${S5_HOG_NAME:-indexer-warmup}"
hog_mb="${S5_HOG_MB:-256}"
pidfile="$(lab_state_dir "$ID")/hog.pid"

# 1. The actual fault: a limit on the API's own cgroup.
if [[ "$(svc_mode nurse)" == "compose" ]]; then
  override="${NURSE_DIR:?}/compose.override.yaml"
  if [[ -f "$override" ]]; then
    lab_backup_file "$ID" "$override"
  else
    lab_state_set "$ID" CREATED_OVERRIDE 1
  fi
  printf 'services:\n  %s:\n    mem_limit: 48m\n    memswap_limit: 48m\n' \
    "$(svc_name nurse api)" >"$override"
  svc_compose nurse up -d --force-recreate "$(svc_name nurse api)" >/dev/null 2>&1 || true
else
  unit="$(svc_name nurse api)"
  dir="/etc/systemd/system/${unit}.d"
  lab_as_root mkdir -p "$dir"
  printf '[Service]\nMemoryMax=48M\nMemorySwapMax=0\n' |
    lab_as_root tee "${dir}/90-lab.conf" >/dev/null
  lab_state_set "$ID" DROPIN "${dir}/90-lab.conf"
  lab_as_root systemctl daemon-reload
  svc_restart nurse api >/dev/null 2>&1 || true
fi

# 2. The red herring: bounded, non-growing, and obvious in top.
if [[ ! -f "$pidfile" ]] || ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
# Values are passed as positional parameters rather than interpolated
# into the script text: safer, and $1/$2 below are deliberate.
# shellcheck disable=SC2016
  lab_as_root bash -c '
    exec -a "$1" python3 -c "
import sys, time
mb = int(sys.argv[1])
block = bytearray(mb * 1024 * 1024)   # allocated once, never grown
for i in range(0, len(block), 4096):
    block[i] = 1
while True:
    time.sleep(3600)
" "$2" &
    echo $! > "$3"
  ' _ "$hog_name" "$hog_mb" "$pidfile"
fi

lab_state_set "$ID" HOG_PID "$(cat "$pidfile" 2>/dev/null || true)"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
