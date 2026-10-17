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

# assert_above <description> <actual> <floor> [unit]
assert_above() {
  local desc="$1" actual="$2" floor="$3" unit="${4:-}"
  if awk -v a="$actual" -v f="$floor" 'BEGIN{exit !(a+0 > f+0)}'; then
    assert_pass "$desc (${actual}${unit} > ${floor}${unit})"
  else
    assert_fail "$desc" "${actual}${unit} is not above ${floor}${unit}"
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

# health_check — one definition of "the lab is healthy".
#
# Called by `lab chaos --check`, where a round that fired nothing is passed by
# proving health rather than by finding a fault, and by the stage 8 acceptance
# suite. Keeping it in one place is the point: two definitions of healthy would
# mean a chaos round could pass while the acceptance suite failed.
#
# Needs lab.conf sourced, and lib/svc.sh for the service checks.
health_check() {
  local app mode unit seen="" port users u pct

  # --- the three applications answer -------------------------------------
  assert_http "stages answers"         "${STAGES_URL:?}" 200
  assert_http "leaves answers"         "${LEAVES_URL:?}" 200
  assert_http "the theses API answers" "${NURSE_API:?}"  200
  [[ -z "${NURSE_WEB:-}" ]] || assert_http "the theses site answers" "$NURSE_WEB" 200

  # --- every expected service is running, and will come back after a boot --
  for app in stages leaves nurse; do
    local modevar="${app^^}_MODE"
    mode="${!modevar:-${RUN_MODE:-}}"
    if [[ "$mode" == "systemd" ]]; then
      local unitvar
      for unitvar in "${app^^}_API_UNIT" "${app^^}_WEB_UNIT"; do
        unit="${!unitvar:-}"
        [[ -n "$unit" ]] || continue
        [[ " $seen " != *" $unit "* ]] || continue
        seen+=" $unit"
        assert_cmd "${unit} is running" systemctl is-active --quiet "$unit"
        assert_cmd "${unit} is enabled at boot" systemctl is-enabled --quiet "$unit"
      done
    else
      assert_service "${app}'s api is running" "$app" api
      assert_service "${app}'s web is running" "$app" web
    fi
  done
  assert_cmd "nginx is running" systemctl is-active --quiet "${NGINX_UNIT:-nginx.service}"
  assert_cmd "the database is running" systemctl is-active --quiet "${DB_UNIT:-postgresql.service}"

  # --- resources, as measurements ----------------------------------------
  pct="$(df -P / | awk 'NR==2{gsub("%","",$5); print $5+0}')"
  assert_below "the root filesystem has room" "$pct" "${HEALTH_DISK_PCT:-80}" "%"
  pct="$(df -Pi / | awk 'NR==2{gsub("%","",$5); print $5+0}')"
  assert_below "the root filesystem has inodes" "$pct" "${HEALTH_INODE_PCT:-80}" "%"
  pct="$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)"
  assert_above "memory available is above the floor" "$pct" "${HEALTH_MEM_MIN_MB:-256}" "MB"
  pct="$(awk -v c="$(nproc)" '{printf "%.2f", $1/c}' /proc/loadavg)"
  assert_below "load average per core is sane" "$pct" "${HEALTH_LOAD_PER_CORE:-2.0}"

  # --- nothing listening that should not be ------------------------------
  if [[ -n "${EXPECTED_PORTS:-}" ]]; then
    local unexpected=""
    while read -r port; do
      [[ -n "$port" ]] || continue
      [[ " ${EXPECTED_PORTS} " != *" ${port} "* ]] || continue
      unexpected+="${port} "
    done < <(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un)
    if [[ -z "$unexpected" ]]; then
      assert_pass "no unexpected listening ports"
    else
      assert_fail "no unexpected listening ports" \
        "listening and not in EXPECTED_PORTS: ${unexpected}— sudo ss -ltnp to see what owns them"
    fi
  else
    printf 'SKIP  EXPECTED_PORTS is not set in lab.conf, so ports were not checked\n'
  fi

  # --- and no accounts that should not be there --------------------------
  if [[ -n "${EXPECTED_USERS:-}" ]]; then
    local extra=""
    while read -r u; do
      [[ -n "$u" ]] || continue
      [[ " ${EXPECTED_USERS} " != *" ${u} "* ]] || continue
      extra+="${u} "
    done < <(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd | sort)
    if [[ -z "$extra" ]]; then
      assert_pass "no unexpected user accounts"
    else
      assert_fail "no unexpected user accounts" \
        "not in EXPECTED_USERS: ${extra}— getent passwd <name>, and check their shell and keys"
    fi
  else
    printf 'SKIP  EXPECTED_USERS is not set in lab.conf, so accounts were not checked\n'
  fi
  users="$(awk -F: '$3==0 {print $1}' /etc/passwd | grep -vx root | tr '\n' ' ')"
  if [[ -z "$users" ]]; then
    assert_pass "root is the only uid 0"
  else
    assert_fail "root is the only uid 0" "also uid 0: ${users}"
  fi

  # --- the things that fail silently -------------------------------------
  health_file_fresh "the backup marker is fresh" "${BACKUP_MARKER:-}" "${BACKUP_MAX_AGE_H:-30}"
  health_file_fresh "the nightly report is fresh" "${LAB_JOB_OUT:-}" "${LAB_JOB_MAX_AGE_H:-30}"
}

# health_file_fresh <description> <path> <max age hours>
# Unset path means "not built yet", which is reported rather than failed: the
# backup marker does not exist until stage 7 has been done.
health_file_fresh() {
  local desc="$1" path="${2:-}" max_h="${3:-30}" age_h
  if [[ -z "$path" ]]; then
    printf 'SKIP  %s — not configured in lab.conf yet\n' "$desc"
    return 0
  fi
  if [[ ! -e "$path" ]]; then
    assert_fail "$desc" "${path} does not exist — whatever writes it has never succeeded"
    return 0
  fi
  age_h=$(( ( $(date +%s) - $(stat -c '%Y' "$path") ) / 3600 ))
  assert_below "$desc" "$age_h" "$max_h" "h"
}
