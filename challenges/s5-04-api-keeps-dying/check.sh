#!/usr/bin/env bash
# s5-04 — check: the hog is gone, the API's memory limit is sane, and the API
# survives a window without being killed. Both absence claims are proved
# against a planted instance first.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s5-04-api-keeps-dying'
hog_name="${S5_HOG_NAME:-indexer-warmup}"
window="${S5_SURVIVE_SECONDS:-180}"
floor_mb="${S5_MEM_FLOOR_MB:-256}"
ctl_pidfile="$(lab_state_dir "$ID")/control.pid"
ctl_cg="/sys/fs/cgroup/lab-oom-control"
OOM_MARK="0"

# --- the red herring must be gone, and the detector must be shown to work ---
detect_hog() { lab_as_root pgrep -f "$hog_name" >/dev/null 2>&1; }
plant_hog()  {
  # shellcheck disable=SC2016  # $1/$2 are the inner script's parameters
  lab_as_root bash -c 'exec -a "$1" sleep 90 & echo $! >"$2"' _ "$hog_name" "$ctl_pidfile"
  sleep 1
}
clean_hog()  {
  [[ -f "$ctl_pidfile" ]] || return 0
  lab_as_root kill "$(cat "$ctl_pidfile")" 2>/dev/null || true
  rm -f "$ctl_pidfile"; sleep 1
}
assert_absent "the memory hog is gone" detect_hog plant_hog clean_hog

# --- the limit on the API's own cgroup is no longer the fault ----------------
limit_bytes=""
if [[ "$(svc_mode nurse)" == "compose" ]]; then
  cid="$(svc_compose nurse ps -q "$(svc_name nurse api)" 2>/dev/null | head -1 || true)"
  [[ -z "$cid" ]] || limit_bytes="$(lab_as_root docker inspect -f '{{.HostConfig.Memory}}' "$cid" 2>/dev/null || true)"
else
  limit_bytes="$(systemctl show -p MemoryMax --value "$(svc_name nurse api)" 2>/dev/null || true)"
  [[ "$limit_bytes" != "infinity" ]] || limit_bytes=0
fi

if [[ -z "$limit_bytes" ]]; then
  assert_fail "the API's memory limit is sane" "could not read the limit"
elif [[ "$limit_bytes" == "0" ]]; then
  assert_pass "the API's memory limit is sane (no limit set)"
elif (( limit_bytes >= floor_mb * 1024 * 1024 )); then
  assert_pass "the API's memory limit is sane ($(( limit_bytes / 1024 / 1024 ))MB)"
else
  assert_fail "the API's memory limit is sane" \
    "it is $(( limit_bytes / 1024 / 1024 ))MB, below the ${floor_mb}MB floor: the cgroup OOM killer will keep picking the API"
fi

# --- no OOM kills while we watch, with the detector proved -------------------
# A kernel log is append-only, so the control's cleanup advances the mark past
# the event it planted rather than deleting it.
detect_oom() {
  lab_as_root dmesg 2>/dev/null \
    | grep -E 'oom-kill:|Memory cgroup out of memory' \
    | sed -E 's/^\[[[:space:]]*([0-9]+)\..*/\1/' \
    | awk -v m="$OOM_MARK" '$1+0 > m {found=1} END{exit !found}'
}
plant_oom() {
  OOM_MARK="$(awk '{printf "%d", $1}' /proc/uptime)"
  if [[ -d /run/systemd/system ]] && command -v systemd-run >/dev/null 2>&1; then
    lab_as_root systemd-run --scope -q -p MemoryMax=8M -p MemorySwapMax=0 -- \
      python3 -c 'bytearray(64*1024*1024)' >/dev/null 2>&1 || true
  else
    lab_as_root mkdir -p "$ctl_cg" 2>/dev/null || true
    # shellcheck disable=SC2016  # $1 is the inner script's parameter
    lab_as_root bash -c 'echo 8M > "$1/memory.max" 2>/dev/null; echo 0 > "$1/memory.swap.max" 2>/dev/null
      ( echo $BASHPID > "$1/cgroup.procs" 2>/dev/null && exec python3 -c "bytearray(64*1024*1024)" ) >/dev/null 2>&1' \
      _ "$ctl_cg" || true
  fi
  sleep 2
}
clean_oom() {
  lab_as_root rmdir "$ctl_cg" 2>/dev/null || true
  OOM_MARK="$(awk '{printf "%d", $1}' /proc/uptime)"
}

# --- the API survives the window without its restart counter moving ----------
restarts_now() {
  if [[ "$(svc_mode nurse)" == "compose" ]]; then
    local c; c="$(svc_compose nurse ps -q "$(svc_name nurse api)" 2>/dev/null | head -1 || true)"
    if [[ -z "$c" ]]; then printf 'unknown\n'
    else lab_as_root docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null; fi
  else
    systemctl show -p NRestarts --value "$(svc_name nurse api)" 2>/dev/null
  fi
}

before="$(restarts_now)"
OOM_MARK="$(awk '{printf "%d", $1}' /proc/uptime)"
printf 'watching the API for %ss (restart counter and the kernel log)...\n' "$window"
sleep "$window"
after="$(restarts_now)"

assert_equal "the API was not restarted during the ${window}s window (counter ${before})" \
  "$after" "$before"
assert_http "the API is answering at the end of the window" "${NURSE_API:?}" 200
assert_absent "nothing was OOM-killed during the window" detect_oom plant_oom clean_oom

assert_summary
