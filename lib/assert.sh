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

ASSERT_PASSED=0
ASSERT_FAILED=0

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
  out="$("$@" 2>&1)" || status=$?
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
  if "$@" >/dev/null 2>&1; then assert_fail "$desc" "command unexpectedly succeeded"
  else assert_pass "$desc"; fi
}

# assert_http <description> <url> [expected status] [timeout]
assert_http() {
  local desc="$1" url="$2" want="${3:-200}" timeout="${4:-10}" got
  got="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || true)"
  if [[ "$got" == "$want" ]]; then assert_pass "$desc ($url → $got)"
  else assert_fail "$desc" "$url returned '${got:-no response}', wanted $want"; fi
}

# assert_http_body <description> <url> <extended regex>
assert_http_body() {
  local desc="$1" url="$2" re="$3" body
  body="$(curl -sS --max-time 10 "$url" 2>/dev/null || true)"
  if grep -Eq "$re" <<<"$body"; then assert_pass "$desc"
  else assert_fail "$desc" "$url body did not match /${re}/"; fi
}

# assert_http_header <description> <url> <header regex>
assert_http_header() {
  local desc="$1" url="$2" re="$3" headers
  headers="$(curl -sSI --max-time 10 "$url" 2>/dev/null || true)"
  if grep -Eqi "$re" <<<"$headers"; then assert_pass "$desc"
  else assert_fail "$desc" "no header matching /${re}/ from $url"; fi
}

# assert_eventually <description> <timeout seconds> <command...>
# For end states that take a moment: a service coming up, a port opening.
assert_eventually() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0
  while (( waited < timeout )); do
    if "$@" >/dev/null 2>&1; then assert_pass "$desc (after ${waited}s)"; return 0; fi
    sleep 2; waited=$(( waited + 2 ))
  done
  assert_fail "$desc" "still failing after ${timeout}s"
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
  if svc_is_active "$app" "$role" >/dev/null 2>&1; then assert_pass "$desc"
  else assert_fail "$desc" "$app:$role is not running"; fi
}
