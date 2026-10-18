#!/usr/bin/env bash
# s2-03 — check: run it healthy, run it with the thresholds forced, and run it
# with an application genuinely stopped.
#
# The stopped application is started again by an EXIT trap rather than at the
# end of the happy path, because a check that leaves an application down
# because one of its own assertions misbehaved is worse than no check.
set -euo pipefail
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

ID='s2-03-appcheck-script'
script="${S2_BIN_DIR:-/usr/local/bin}/appcheck.sh"
stop_app="${S2_03_STOP_APP:-leaves}"
state="$(lab_state_dir "$ID")"
# Not named `out`: assert_cmd declares a local of that name, and a callback
# reading it aborts under set -u. See the note in lib/assert.sh.
healthy="$state/run-healthy"
failing="$state/run-failing"
warned="$state/run-warned"
stopped=0

restore() {
  (( stopped == 1 )) || return 0
  svc_start "$stop_app" web >/dev/null 2>&1 || true
  svc_start "$stop_app" api >/dev/null 2>&1 || true
}
trap restore EXIT

assert_file "the script exists at ${script}" "$script"
if [[ ! -f "$script" ]]; then
  assert_summary
  exit $?
fi
assert_cmd "it is executable" test -x "$script"

# --- 1. everything up ------------------------------------------------------
run_healthy() { "$script" >"$healthy" 2>&1; }
assert_cmd "with all three up it exits 0" run_healthy

if [[ ! -s "$healthy" ]]; then
  assert_fail "it printed something" "no output at all"
  assert_summary
  exit $?
fi

for app in stages leaves nurse; do
  if grep -qE "^.*\b${app}\b" "$healthy"; then
    assert_pass "the healthy run names ${app}"
  else
    assert_fail "the healthy run names ${app}" \
      "nothing in the output mentions it — the first thing anyone does with this output is search it for a name"
  fi
done
no_fail_lines() { ! grep -q 'FAIL' "$healthy"; }
assert_cmd "every healthy line is OK or WARN, none FAIL" no_fail_lines

# --- 2. timestamps ---------------------------------------------------------
ts_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
untimed="$(grep -cvE "$ts_re" "$healthy" || true)"
if [[ "${untimed:-0}" == 0 ]]; then
  assert_pass "every line begins with a timestamp"
else
  assert_fail "every line begins with a timestamp" \
    "${untimed} line(s) do not — output found in a log two days later has to say when it was written"
fi

first_ts="$(grep -oE "$ts_re" "$healthy" | sed -n '1p' | tr 'T' ' ' || true)"
if [[ -z "$first_ts" ]]; then
  assert_fail "the timestamps are from now" "no parseable timestamp in the output"
else
  then_s="$(date -d "$first_ts" +%s 2>/dev/null || echo 0)"
  now_s="$(date +%s)"
  drift=$(( now_s - then_s )); (( drift >= 0 )) || drift=$(( -drift ))
  if (( then_s > 0 )); then
    assert_below "the timestamps are from now, not from the last run" "$drift" 300 "s"
  else
    assert_fail "the timestamps are from now" \
      "'${first_ts}' is not a date this machine can parse — date -Is, or date '+%Y-%m-%dT%H:%M:%S'"
  fi
fi

# --- 3. the warning paths, forced ------------------------------------------
# A threshold that cannot be moved is a threshold that cannot be tested, and a
# monitoring script whose alarm has never fired has never been tested. These
# are positive claims: the warning is made to happen and then required.
total_mb="$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)"
run_warned() {
  APPCHECK_DISK_PCT=0 APPCHECK_MEM_MIN_MB=$(( total_mb * 10 )) \
    "$script" >"$warned" 2>&1 || true
}
assert_cmd "it survives being given thresholds that must trip" run_warned
if [[ -s "$warned" ]]; then
  if grep -qiE '^.*WARN.*(disk|/|filesystem)' "$warned"; then
    assert_pass "APPCHECK_DISK_PCT=0 produces a disk WARN"
  else
    assert_fail "APPCHECK_DISK_PCT=0 produces a disk WARN" \
      "no WARN line about the disk — is the threshold read from the environment with a default, rather than written in?"
  fi
  if grep -qiE '^.*WARN.*(mem|memory)' "$warned"; then
    assert_pass "an impossible memory floor produces a memory WARN"
  else
    assert_fail "an impossible memory floor produces a memory WARN" \
      "no WARN line about memory, with the floor set to $(( total_mb * 10 ))MB on a ${total_mb}MB machine"
  fi
else
  assert_fail "it printed something with the thresholds forced" "no output"
fi

# --- 4. one application actually stopped -----------------------------------
printf 'stopping %s to prove the failure path...\n' "$stop_app"
stopped=1
svc_stop "$stop_app" web >/dev/null 2>&1 || true
svc_stop "$stop_app" api >/dev/null 2>&1 || true

# Is it really down? If it is not, the next assertion would be testing nothing
# and passing or failing for reasons that have nothing to do with the script.
stop_url_var="$(printf '%s_URL' "${stop_app^^}")"
stop_url="${!stop_url_var:-}"
[[ -n "$stop_url" ]] || stop_url="${NURSE_API:-}"
down=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$stop_url" 2>/dev/null || true)"
  if [[ "$code" != 200 ]]; then down=1; break; fi
  sleep 2
done

if (( down == 0 )); then
  assert_fail "${stop_app} could be stopped, so the failure path can be tested" \
    "${stop_url} still answers 200 after svc_stop — without a genuinely stopped application this assertion would prove nothing either way"
else
  assert_pass "${stop_app} is stopped (${stop_url} no longer answers)"

  run_failing() { "$script" >"$failing" 2>&1; }
  assert_not "with ${stop_app} down it exits non-zero" run_failing

  if [[ -s "$failing" ]]; then
    if grep -E 'FAIL' "$failing" | grep -qE "\b${stop_app}\b"; then
      assert_pass "the FAIL line names ${stop_app}"
    else
      assert_fail "the FAIL line names ${stop_app}" \
        "there is a failure in the output but it does not say which application — a URL is not a name you can search a log for"
    fi
    # And it carried on: a script that dies at the first curl never reaches
    # the other two, which looks like a working failure path and is not.
    others=0
    for app in stages leaves nurse; do
      [[ "$app" != "$stop_app" ]] || continue
      grep -qE "\b${app}\b" "$failing" && others=$(( others + 1 ))
    done
    if (( others == 2 )); then
      assert_pass "it still checked the other two applications"
    else
      assert_fail "it still checked the other two applications" \
        "only ${others} of the other 2 appear. A bare curl under set -e ends the script at the first refusal: capture the status instead of letting it propagate"
    fi
  else
    assert_fail "it printed something with ${stop_app} down" "no output"
  fi
fi

printf 'starting %s again...\n' "$stop_app"
restore
stopped=0
assert_eventually "${stop_app} is back up" 60 \
  curl -fsS -o /dev/null --max-time 5 "$stop_url"

# --- 5. the script itself --------------------------------------------------
assert_file_matches "it starts with #!/usr/bin/env bash" "$script" '^#!/usr/bin/env bash$'
assert_file_matches "it sets errexit, nounset and pipefail" "$script" '^set -euo pipefail$'
if command -v shellcheck >/dev/null 2>&1; then
  assert_cmd "shellcheck is clean on it" shellcheck -S warning "$script"
else
  printf 'SKIP  shellcheck is not installed: sudo apt install shellcheck\n'
fi

assert_summary
