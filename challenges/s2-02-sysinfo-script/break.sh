#!/usr/bin/env bash
# s2-02 — a mission: nothing is broken. This says where the script goes and
# what the machine's real numbers are right now, so the output can be sanity
# checked against something rather than merely parsed.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-02-sysinfo-script'
script="${S2_BIN_DIR:-/usr/local/bin}/sysinfo.sh"

printf 'Nothing is broken: this is a mission.\n\n'
printf 'Write it here, and make it executable:\n  %s\n\n' "$script"

if [[ -e "$script" ]]; then
  printf 'Something is already there (%s bytes). Not touched.\n\n' \
    "$(stat -c '%s' "$script")"
fi

printf 'What this machine will say if you ask it correctly:\n'
printf '  hostname        %s\n' "$(hostname)"
printf '  uptime_seconds  %s\n' "$(awk '{printf "%d", $1}' /proc/uptime)"
printf '  load_1min       %s\n' "$(awk '{print $1}' /proc/loadavg)"
printf '  disk_used_pct   %s\n' "$(df -P / | awk 'NR==2{gsub("%","",$5); print $5+0}')"
printf '  memtotal_mb     %s\n' "$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)"
printf '  memavailable_mb %s\n' "$(awk '/^MemAvailable:/{printf "%d", $2/1024}' /proc/meminfo)"

printf '\nThose last two are the ingredients, not the answer: "memory used" has\n'
printf 'more than one defensible definition and the brief asks you to pick one.\n'

printf '\nWhen it works:\n  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
