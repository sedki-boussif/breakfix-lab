#!/usr/bin/env bash
# s5-05 — check: load average back under the core count, every app answering
# inside a second, and no process burning a core. The detector samples CPU
# time rather than matching a name, because the name is what this challenge
# teaches you to distrust.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s5-05-everything-is-slow'
cores="$(nproc)"
ctl_pidfile="$(lab_state_dir "$ID")/control.pid"

# Any process that consumed more than 80% of a core over a two-second window.
# The comm field in /proc/<pid>/stat can contain spaces and parentheses, which
# shifts every field after it, so it is stripped before the fields are counted.
cpu_snapshot() {
  local f
  for f in /proc/[0-9]*/stat; do
    awk '{ rest = $0; sub(/^[0-9]+ \(.*\) /, "", rest); split(rest, c, " ");
           print $1, c[12] + c[13] }' "$f" 2>/dev/null || true
  done
}
detect_spinner() {
  local ticks threshold t1 t2 rc
  ticks="$(getconf CLK_TCK)"
  threshold=$(( ticks * 2 * 80 / 100 ))
  t1="$(mktemp)"; t2="$(mktemp)"
  cpu_snapshot >"$t1"; sleep 2; cpu_snapshot >"$t2"
  if awk -v th="$threshold" '
        NR==FNR { before[$1] = $2; next }
        ($1 in before) && ($2 - before[$1]) > th { print $1; found = 1 }
        END { exit !found }' "$t1" "$t2"; then
    rc=0
  else
    rc=1
  fi
  rm -f "$t1" "$t2"
  return "$rc"
}
plant_spinner() {
  # shellcheck disable=SC2016  # the loop body must not be expanded here
  setsid bash -c 'exec -a lab-absence-control bash -c "while :; do :; done"' _ &
  echo $! >"$ctl_pidfile"
  sleep 1
}
clean_spinner() {
  [[ -f "$ctl_pidfile" ]] || return 0
  lab_as_root pkill -P "$(cat "$ctl_pidfile")" 2>/dev/null || true
  lab_as_root kill "$(cat "$ctl_pidfile")" 2>/dev/null || true
  lab_as_root pkill -f lab-absence-control 2>/dev/null || true
  rm -f "$ctl_pidfile"; sleep 1
}
assert_absent "no process is burning a core" detect_spinner plant_spinner clean_spinner

# Load average decays, so give it room rather than failing on the first read.
load_ok() { awk -v c="$cores" '{exit !($1 < c)}' /proc/loadavg; }
assert_eventually "load average is back under the core count (${cores})" 180 load_ok

# "Slow" becomes a number, for each app.
assert_responds_fast() {
  local name="$1" url="$2" t
  t="$(curl -sS -o /dev/null -w '%{time_total}' --max-time 10 "$url" 2>/dev/null || echo 99)"
  assert_below "$name answers in under a second" "$t" 1.0 "s"
}
assert_responds_fast stages "${STAGES_URL:?}"
assert_responds_fast leaves "${LEAVES_URL:?}"
assert_responds_fast nurse  "${NURSE_API:?}"

assert_summary
