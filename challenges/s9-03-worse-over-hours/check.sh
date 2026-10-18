#!/usr/bin/env bash
# s9-03 — check: the growth RATE is flat, not the current size. Truncating the
# file and leaving the writer running fails here, which is the point.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s9-03-worse-over-hours'
mnt="$(lab_fs_mnt growth)"
window="${S9_03_WINDOW:-120}"
max_rate="${S9_03_MAX_KB_PER_MIN:-64}"
report="$LAB_ROOT/reports/${ID}.md"
ctl="$(lab_state_dir "$ID")/control"

if ! mountpoint -q "$mnt" 2>/dev/null; then
  printf 'The growth filesystem is not mounted at %s.\n' "$mnt" >&2
  printf 'Run: lab reset %s\n' "$ID" >&2
  exit 1
fi

# Kilobytes used on that filesystem, which is what actually runs out.
used_kb() { df -Pk "$mnt" | awk 'NR==2{print $3}'; }

# The rate detector, in kB per minute over a window.
rate_kb_min() {
  local secs="${1:-30}" a b
  a="$(used_kb)"; sleep "$secs"; b="$(used_kb)"
  awk -v a="$a" -v b="$b" -v s="$secs" 'BEGIN{printf "%.1f", (b-a)*60/s}'
}

# Absence claim, so the detector is proved against a writer planted on purpose.
detect_growth() {
  local r; r="$(rate_kb_min 20)"
  awk -v r="$r" -v m="$max_rate" 'BEGIN{exit !(r+0 > m+0)}'
}
plant_growth() {
  # shellcheck disable=SC2016  # $1 and $2 are the inner script's parameters
  lab_as_root bash -c '
    echo $$ >"$2"
    exec -a lab-growth-control bash -c "
      while :; do head -c 262144 /dev/urandom | base64 -w0 >> \"\$1\"; sleep 0.05; done
    " _ "$1"
  ' _ "${mnt}/.lab-growth-control" "${ctl}.pid" &
  sleep 2
}
clean_growth() {
  [[ -f "${ctl}.pid" ]] || return 0
  lab_as_root pkill -P "$(cat "${ctl}.pid")" 2>/dev/null || true
  lab_as_root kill "$(cat "${ctl}.pid")" 2>/dev/null || true
  lab_as_root pkill -f lab-growth-control 2>/dev/null || true
  rm -f "${ctl}.pid"
  lab_as_root rm -f "${mnt}/.lab-growth-control"
  sleep 1
}
assert_absent "nothing is growing on that filesystem" \
  detect_growth plant_growth clean_growth

# And the measured rate itself, over the stated window, in the output.
printf 'measuring the growth rate over %ss...\n' "$window"
r="$(rate_kb_min "$window")"
assert_below "the growth rate is flat" "$r" "$max_rate" " kB/min"

# The filesystem has room, which is the symptom the reporter actually felt.
assert_below "that filesystem has room" "$(lab_fs_pct "$mnt")" 80 "%"

# The rate before and after is the only proof the cause was dealt with.
if [[ -f "$report" ]]; then
  assert_file_matches "the report states the growth rate before and after" \
    "$report" 'kB|MB|per (minute|hour)|rate'
  assert_file_matches "the report says whether the cause is fixed or only bounded" \
    "$report" 'logrotate|bounded|contain|cause|writer'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # a rate before and after, and whether you fixed or bounded it"
fi

assert_summary
