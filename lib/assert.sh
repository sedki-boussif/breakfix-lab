#!/usr/bin/env bash
# assert.sh — assertion helpers for check.sh scripts.
#
# A check prints one line per assertion and nothing else. Assertions never
# abort the script: they record a failure and carry on, so one run tells you
# everything that is still wrong. assert_summary sets the exit status: 0 all
# passed, 1 anything failed.
#
#   . lib/assert.sh
#   assert_http "the leave app answers" "$LEAVES_URL" 200
#   assert_summary
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

ASSERT_PASSED=0
ASSERT_FAILED=0

# Every assertion runs under a hard deadline. A rule in the documentation did
# not stop an lsof scan hanging for twenty minutes; this does. A hang becomes a
# FAIL, because a failure is information and a hang is a drill abandoned.
ASSERT_TIMEOUT="${ASSERT_TIMEOUT:-30}"

# _assert_deadline <seconds> <command...>
#
# Runs the command in a subshell with a watchdog, and returns 124 if the
# deadline passed. A subshell inherits the caller's functions and variables, so
# detectors and planters need no exporting — but anything they must persist has
# to go to a file, because variable changes do not come back out.
_assert_deadline() {
  local secs="$1"; shift
  local pid watchdog rc=0
  ( "$@" ) & pid=$!
  (
    # No "local" here: this is a subshell, not a function, and local would
    # abort it immediately — which is exactly how the first version of this
    # watchdog silently did nothing at all, and the hang survived.
    waited=0
    while (( waited < secs )); do
      kill -0 "$pid" 2>/dev/null || exit 0
      sleep 1
      waited=$(( waited + 1 ))
    done
    pkill -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    pkill -9 -P "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  ) & watchdog=$!
  wait "$pid" 2>/dev/null || rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  case "$rc" in
    143|137) rc=124 ;;   # the watchdog reached it
  esac
  return "$rc"
}

assert_timed_out() {
  ASSERT_FAILED=$(( ASSERT_FAILED + 1 ))
  printf '%sFAIL%s  %s\n' "$ASSERT_RED" "$ASSERT_OFF" "$1"
  printf '      assertion timed out after %ss\n' "$2"
}

if [[ -t 1 ]]; then
  ASSERT_GREEN=$'\033[32m'; ASSERT_RED=$'\033[31m'; ASSERT_OFF=$'\033[0m'
else
  ASSERT_GREEN=''; ASSERT_RED=''; ASSERT_OFF=''
fi

assert_pass() {
  ASSERT_PASSED=$(( ASSERT_PASSED + 1 ))
  printf '%sPASS%s  %s\n' "$ASSERT_GREEN" "$ASSERT_OFF" "$1"
}

# assert_fail <description> [why]
assert_fail() {
  ASSERT_FAILED=$(( ASSERT_FAILED + 1 ))
  printf '%sFAIL%s  %s\n' "$ASSERT_RED" "$ASSERT_OFF" "$1"
  [[ -z "${2:-}" ]] || printf '      %s\n' "$2"
}

assert_summary() {
  printf '\n%d passed, %d failed\n' "$ASSERT_PASSED" "$ASSERT_FAILED"
  (( ASSERT_FAILED == 0 ))
}

# assert_cmd <description> <command...>  — passes when the command exits 0.
assert_cmd() {
  local desc="$1"; shift
  local out status=0
  out="$(_assert_deadline "$ASSERT_TIMEOUT" "$@" 2>&1)" || status=$?
  if (( status == 124 )); then
    assert_timed_out "$desc" "$ASSERT_TIMEOUT"; return 0
  fi
  if (( status == 0 )); then
    assert_pass "$desc"
  elif [[ -n "$out" ]]; then
    assert_fail "$desc" "exit ${status}: $(head -2 <<<"$out" | tr '\n' ' ')"
  else
    assert_fail "$desc" "exit ${status}, no output"
  fi
}

# assert_not <description> <command...> — passes when the command exits non-zero.
assert_not() {
  local desc="$1"; shift
  local status=0
  _assert_deadline "$ASSERT_TIMEOUT" "$@" >/dev/null 2>&1 || status=$?
  if (( status == 124 )); then assert_timed_out "$desc" "$ASSERT_TIMEOUT"
  elif (( status == 0 )); then assert_fail "$desc" "command unexpectedly succeeded"
  else assert_pass "$desc"; fi
}

# assert_http <description> <url> [expected status] [timeout]
assert_http() {
  local desc="$1" url="$2" want="${3:-200}" timeout="${4:-10}" got
  got="$(_assert_deadline "$ASSERT_TIMEOUT" curl -sS -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || true)"
  if [[ "$got" == "$want" ]]; then assert_pass "$desc ($url → $got)"
  else assert_fail "$desc" "$url returned '${got:-no response}', wanted $want"; fi
}

# assert_http_body <description> <url> <extended regex>
assert_http_body() {
  local desc="$1" url="$2" re="$3" body
  body="$(_assert_deadline "$ASSERT_TIMEOUT" curl -sS --max-time 10 "$url" 2>/dev/null || true)"
  if grep -Eq "$re" <<<"$body"; then assert_pass "$desc"
  else assert_fail "$desc" "$url body did not match /${re}/"; fi
}

# assert_http_header <description> <url> <header regex>
# Uses a GET with the headers dumped rather than a HEAD request: not every
# application answers HEAD, and what matters is the response a browser gets.
assert_http_header() {
  local desc="$1" url="$2" re="$3" headers
  headers="$(_assert_deadline "$ASSERT_TIMEOUT" curl -sS -D - -o /dev/null --max-time 10 "$url" 2>/dev/null || true)"
  if grep -Eqi "$re" <<<"$headers"; then assert_pass "$desc"
  else assert_fail "$desc" "no header matching /${re}/ from $url"; fi
}

# assert_eventually <description> <timeout seconds> <command...>
# For end states that take a moment: a service coming up, a port opening.
assert_eventually() {
  local desc="$1" window="$2"; shift 2
  local waited=0 status=0
  while (( waited < window )); do
    status=0
    _assert_deadline "$ASSERT_TIMEOUT" "$@" >/dev/null 2>&1 || status=$?
    if (( status == 0 )); then assert_pass "$desc (after ${waited}s)"; return 0; fi
    if (( status == 124 )); then
      assert_timed_out "$desc" "$ASSERT_TIMEOUT"; return 0
    fi
    sleep 2; waited=$(( waited + 2 ))
  done
  assert_fail "$desc" "still failing after ${window}s"
}

assert_file() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then assert_pass "$desc"
  else assert_fail "$desc" "no such file: $path"; fi
}

# assert_file_matches <description> <path> <extended regex>
assert_file_matches() {
  local desc="$1" path="$2" re="$3"
  if [[ -f "$path" ]] && grep -Eq "$re" "$path"; then assert_pass "$desc"
  else assert_fail "$desc" "$path does not match /${re}/"; fi
}

# assert_numeric <description> <value>
assert_numeric() {
  local desc="$1" value="${2:-}"
  if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then assert_pass "$desc (=$value)"
  else assert_fail "$desc" "'${value}' is not a number"; fi
}

# assert_below <description> <actual> <limit> [unit]
assert_below() {
  local desc="$1" actual="$2" limit="$3" unit="${4:-}"
  if awk -v a="$actual" -v l="$limit" 'BEGIN{exit !(a+0 < l+0)}'; then
    assert_pass "$desc (${actual}${unit} < ${limit}${unit})"
  else
    assert_fail "$desc" "${actual}${unit} is not below ${limit}${unit}"
  fi
}

# assert_equal <description> <actual> <expected>
assert_equal() {
  local desc="$1" actual="${2:-}" expected="${3:-}"
  if [[ "$actual" == "$expected" ]]; then assert_pass "$desc"
  else assert_fail "$desc" "got '${actual}', wanted '${expected}'"; fi
}

# assert_service <description> <app> [role] — uses lib/svc.sh.
assert_service() {
  local desc="$1" app="$2" role="${3:-web}"
  local status=0
  _assert_deadline "$ASSERT_TIMEOUT" svc_is_active "$app" "$role" >/dev/null 2>&1 || status=$?
  if (( status == 124 )); then assert_timed_out "$desc" "$ASSERT_TIMEOUT"
  elif (( status == 0 )); then assert_pass "$desc"
  else assert_fail "$desc" "$app:$role is not running"; fi
}

# assert_absent <description> <detect_fn> <plant_fn> <clean_fn>
#
# Absence is only meaningful if the search works. This plants a known instance,
# requires the detector to find it, removes it, and only then asserts that
# nothing is left. A detector that cannot see a planted instance fails loudly
# instead of passing silently — the bug class that makes a green check worthless.
#
# All four arguments are shell function names. detect_fn exits 0 when it FINDS
# something.
assert_absent() {
  local desc="$1" detect="$2" plant="$3" clean="$4"
  local status=0

  # Already present? Then the answer is known and no control is needed.
  status=0; _assert_deadline "$ASSERT_TIMEOUT" "$detect" >/dev/null 2>&1 || status=$?
  if (( status == 124 )); then assert_timed_out "$desc (detector)" "$ASSERT_TIMEOUT"; return 0; fi
  if (( status == 0 )); then assert_fail "$desc" "still present"; return 0; fi

  status=0; _assert_deadline "$ASSERT_TIMEOUT" "$plant" >/dev/null 2>&1 || status=$?
  if (( status == 124 )); then assert_timed_out "$desc (planting the control)" "$ASSERT_TIMEOUT"; return 0; fi

  status=0; _assert_deadline "$ASSERT_TIMEOUT" "$detect" >/dev/null 2>&1 || status=$?
  if (( status == 124 )); then
    _assert_deadline "$ASSERT_TIMEOUT" "$clean" >/dev/null 2>&1 || true
    assert_timed_out "$desc (detector, against the control)" "$ASSERT_TIMEOUT"; return 0
  fi
  if (( status != 0 )); then
    _assert_deadline "$ASSERT_TIMEOUT" "$clean" >/dev/null 2>&1 || true
    assert_fail "$desc" \
      "cannot verify absence: ${detect} did not find an instance planted on purpose, so a clean result means nothing"
    return 0
  fi
  _assert_deadline "$ASSERT_TIMEOUT" "$clean" >/dev/null 2>&1 || true

  status=0; _assert_deadline "$ASSERT_TIMEOUT" "$detect" >/dev/null 2>&1 || status=$?
  if (( status == 124 )); then assert_timed_out "$desc (detector, after cleanup)" "$ASSERT_TIMEOUT"
  elif (( status == 0 )); then
    assert_fail "$desc" "the planted control could not be removed, so the result is inconclusive"
  else
    assert_pass "$desc (detector proved against a planted instance)"
  fi
}
