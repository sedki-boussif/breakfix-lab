#!/usr/bin/env bash
# s2-02 — check: run it as an ordinary user, parse what it printed, and hold
# every number to being a number and to being plausible. Plus shellcheck,
# because the repository holds itself to that and a script that reports on a
# machine is one you will trust later.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s2-02-sysinfo-script'
script="${S2_BIN_DIR:-/usr/local/bin}/sysinfo.sh"
outfile="$(lab_state_dir "$ID")/output"
outfile2="$(lab_state_dir "$ID")/output-second-run"

assert_file "the script exists at ${script}" "$script"
if [[ ! -f "$script" ]]; then
  assert_summary
  exit $?
fi
assert_cmd "it is executable" test -x "$script"

# Run it as an ordinary user, under the library's deadline — a script someone
# has just written is exactly the kind that hangs. A sysinfo script that needs
# root is one you cannot run while working out whether you have root.
run_script()        { "$script" >"$outfile"  2>&1; }
run_script_again()  { "$script" >"$outfile2" 2>&1; }
assert_cmd "it runs and exits 0 without sudo" run_script

if [[ ! -s "$outfile" ]]; then
  assert_fail "it printed something" "no output at all — ${outfile} is empty"
  assert_summary
  exit $?
fi

value() { sed -n "s/^${1}:[[:space:]]*//p" "$outfile" | sed -n '1p' | tr -d '[:space:]'; }

# --- the five scalars, present and numeric ----------------------------------
for key in hostname uptime_seconds load_1min memory_used_mb disk_used_pct; do
  if grep -qE "^${key}:" "$outfile"; then
    assert_pass "${key} is reported"
  else
    assert_fail "${key} is reported" "no line starting '${key}:' in the output"
  fi
done

host="$(value hostname)"
if [[ -n "$host" ]]; then
  assert_equal "hostname matches this machine" "$host" "$(hostname)"
else
  assert_fail "hostname matches this machine" "hostname was empty"
fi

uptime_s="$(value uptime_seconds)"
assert_numeric "uptime_seconds is a number" "$uptime_s"
[[ ! "$uptime_s" =~ ^[0-9]+$ ]] ||
  assert_above "uptime_seconds is a real uptime, not a timestamp" "$uptime_s" 0 "s"
if [[ "$uptime_s" =~ ^[0-9]+$ ]]; then
  # A Unix timestamp where an uptime belongs is the classic form of this bug:
  # date +%s instead of /proc/uptime. It is numeric, plausible-looking, and
  # claims the machine booted in 1970.
  assert_below "uptime_seconds is not a Unix timestamp" "$uptime_s" 1000000000 "s"
fi

load="$(value load_1min)"
assert_numeric "load_1min is a number" "$load"
[[ ! "$load" =~ ^[0-9.]+$ ]] || assert_below "load_1min is plausible" "$load" 1000

disk="$(value disk_used_pct)"
assert_numeric "disk_used_pct is a number, with no % glued to it" "$disk"
if [[ "$disk" =~ ^[0-9]+$ ]]; then
  assert_below "disk_used_pct is at most 100" "$disk" 101 "%"
  real_disk="$(df -P / | awk 'NR==2{gsub("%","",$5); print $5+0}')"
  if (( disk >= real_disk - 2 && disk <= real_disk + 2 )); then
    assert_pass "disk_used_pct agrees with df (${disk}% against ${real_disk}%)"
  else
    assert_fail "disk_used_pct agrees with df" \
      "the script says ${disk}%, df says ${real_disk}% for / — which filesystem is it measuring?"
  fi
fi

mem="$(value memory_used_mb)"
assert_numeric "memory_used_mb is a number of megabytes" "$mem"
if [[ "$mem" =~ ^[0-9]+$ ]]; then
  total_mb="$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)"
  assert_above "memory_used_mb is more than zero" "$mem" 0 " MB"
  assert_below "memory_used_mb is less than the machine has (${total_mb} MB)" \
    "$mem" "$total_mb" " MB"
fi

# --- the process table ------------------------------------------------------
if ! grep -qE '^top_processes:' "$outfile"; then
  assert_fail "top_processes is reported" "no 'top_processes:' line"
else
  assert_pass "top_processes is reported"
  # Everything after the header, non-blank.
  #
  # Parsed by position rather than by hunting for digits. The first version
  # kept any line containing a number and then took the last number on it as
  # the size, which meant "  2  node" — a rank and a name and no size at all —
  # was read as a process using 2 MB. It passed the malformed-line assertion
  # and then quietly corrupted the ordering one. The format is
  # `rank  name  megabytes`, so that is what this requires: a numeric first
  # field, a numeric last field, and at least one field of name between them.
  procs="$(sed -n '/^top_processes:/,$p' "$outfile" | sed '1d' | grep -E '\S' || true)"
  n="$(grep -c . <<<"$procs" || true)"
  assert_equal "top_processes lists exactly five processes" "${n:-0}" "5"

  bad="$(awk 'NF < 3 || $1 !~ /^[0-9]+$/ || $NF !~ /^[0-9]+(\.[0-9]+)?$/ {c++}
              END {print c+0}' <<<"$procs")"
  if (( bad == 0 )); then
    assert_pass "every process line is rank, name and size"
  else
    assert_fail "every process line is rank, name and size" \
      "${bad} line(s) are not — the format is '  1  postgres  412', three fields"
  fi

  # Descending by the size column. Equal sizes are fine: two processes using
  # the same memory is not a mistake.
  desc=1; prev=''
  while read -r line; do
    [[ -n "$line" ]] || continue
    size="$(awk 'NF >= 3 && $NF ~ /^[0-9]+(\.[0-9]+)?$/ {print $NF}' <<<"$line")"
    [[ -n "$size" ]] || continue
    if [[ -n "$prev" ]] && awk -v a="$size" -v b="$prev" 'BEGIN{exit !(a+0 > b+0)}'; then
      desc=0
    fi
    prev="$size"
  done <<<"$procs"
  if (( desc == 1 )); then
    assert_pass "the processes are in descending order"
  else
    assert_fail "the processes are in descending order" \
      "largest first — sort -rn, or ps --sort=-rss"
  fi
fi

# --- the script itself ------------------------------------------------------
assert_file_matches "it starts with #!/usr/bin/env bash" "$script" '^#!/usr/bin/env bash$'
assert_file_matches "it sets errexit, nounset and pipefail" "$script" '^set -euo pipefail$'
if command -v shellcheck >/dev/null 2>&1; then
  assert_cmd "shellcheck is clean on it" shellcheck -S warning "$script"
else
  printf 'SKIP  shellcheck is not installed: sudo apt install shellcheck\n'
fi

# --- and it says the same things twice --------------------------------------
# Not a formality: a script that works once and then does not is usually one
# that left a temporary file behind, or whose first run created something its
# second run tripped over.
assert_cmd "a second run also succeeds" run_script_again
if [[ -s "$outfile2" ]]; then
  keys1="$(grep -oE '^[a-z_]+:' "$outfile"  | sort | tr '\n' ' ')"
  keys2="$(grep -oE '^[a-z_]+:' "$outfile2" | sort | tr '\n' ' ')"
  assert_equal "a second run reports the same keys" "$keys2" "$keys1"
fi

assert_summary
