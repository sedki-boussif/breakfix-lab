#!/usr/bin/env bash
# s2-04 — check: the rule is in the system's set, says what it should say,
# produces a genuinely compressed rotation, and — the assertion that matters —
# leaves the application writing to the new file.
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

ID='s2-04-rotate-the-logs'
log="${LEAVES_LOG:?LEAVES_LOG is not set in lab.conf}"
conf="${S2_04_LOGROTATE_CONF:-/etc/logrotate.d/leaves}"
keep="${S2_04_KEEP:-7}"
url="${LEAVES_URL:-}"
logdir="$(dirname "$log")"
state="$(lab_state_dir "$ID")"
control="${log}.s2-04-control"
control_pid="$state/control-pid"

assert_file "the rule exists at ${conf}" "$conf"
if ! lab_as_root test -f "$conf"; then
  assert_summary
  exit $?
fi

# --- 1. it covers the log, and the system will reach it ---------------------
if lab_as_root grep -qF "$log" "$conf" ||
   lab_as_root grep -qF "${logdir}/*.log" "$conf" ||
   lab_as_root grep -qF "${logdir}/*" "$conf"; then
  assert_pass "the rule names ${log}, or a pattern covering it"
else
  assert_fail "the rule names ${log}, or a pattern covering it" \
    "nothing in ${conf} matches it — logrotate silently ignores a rule for a path that is not there"
fi

# Asked of the whole system rather than of the one file: a rule in a directory
# that logrotate.conf does not include is a file nobody reads. This is also
# the assertion that a rule only working with `-f` by hand cannot satisfy.
sysdebug="$(lab_as_root logrotate --debug /etc/logrotate.conf 2>&1 || true)"
if grep -qF "$log" <<<"$sysdebug"; then
  assert_pass "the system's own logrotate run reaches this rule"
else
  assert_fail "the system's own logrotate run reaches this rule" \
    "${log} does not appear in: sudo logrotate --debug /etc/logrotate.conf — is ${conf} inside the directory logrotate.conf includes, and does its name avoid the suffixes logrotate skips (.dpkg-dist, .rpmsave, anything with a dot in some versions)?"
fi

# It parses. --debug does everything except act, so complaints surface here.
debug="$(lab_as_root logrotate --debug "$conf" 2>&1 || true)"
if grep -qiE 'error|unexpected|unknown option|duplicate log entry' <<<"$debug"; then
  assert_fail "logrotate parses the rule without complaint" \
    "$(grep -iE 'error|unexpected|unknown option|duplicate log entry' <<<"$debug" | sed -n '1,2p' | tr '\n' ' ')"
else
  assert_pass "logrotate parses the rule without complaint"
fi

# --- 2. the three stated properties, from the effective configuration -------
if grep -qiE 'after 1 day|daily' <<<"$debug"; then
  assert_pass "it rotates daily"
else
  assert_fail "it rotates daily" \
    "logrotate --debug ${conf} does not report a daily rotation — 'size' and 'weekly' are both defensible in general and are not what this asks for"
fi
# logrotate 3.21 on Ubuntu 24.04 phrases this as "after 1 days (7 rotations)";
# older builds say "rotation count 7". Both accepted — the number is the claim,
# not the wording of whichever logrotate is installed.
if grep -qE "\(${keep} rotations\)|rotation count ${keep}\b" <<<"$debug"; then
  assert_pass "it keeps ${keep} rotations"
else
  reported="$(grep -oE '\([0-9]+ rotations\)|rotation count [0-9]+' <<<"$debug" | sed -n '1p' || true)"
  assert_fail "it keeps ${keep} rotations" \
    "logrotate --debug reports ${reported:-no rotation count at all}"
fi
if lab_as_root grep -qE '^\s*(compress|delaycompress)\b' "$conf"; then
  assert_pass "it compresses the rotations"
else
  assert_fail "it compresses the rotations" "no compress directive in ${conf}"
fi

# --- 3. force a rotation, and prove the result is really compressed ---------
size_before="$(lab_as_root stat -c '%s' "$log" 2>/dev/null || echo 0)"
printf 'forcing a rotation...\n'
lab_as_root logrotate --force "$conf" >/dev/null 2>&1 || true
sleep 2

base="$(basename "$log")"
rotated="$(lab_as_root find "$logdir" -maxdepth 1 -name "${base}*" \
  ! -name "$base" ! -name "$(basename "$control")" -print 2>/dev/null \
  | sort | sed -n '1p' || true)"

if [[ -z "$rotated" ]]; then
  assert_fail "a forced rotation produced a rotated file" \
    "nothing new alongside ${log} — sudo logrotate --force --verbose ${conf} says why"
else
  assert_pass "a forced rotation produced a rotated file ($(basename "$rotated"))"
fi

# --- 4. the application is still writing. This is the point. ---------------
if [[ -z "$url" ]]; then
  assert_fail "LEAVES_URL is set, so writing can be tested" \
    "the whole mission turns on whether the app writes to the new file, which needs a request to make it write"
else
  size_after_rotate="$(lab_as_root stat -c '%s' "$log" 2>/dev/null || echo 0)"
  printf 'making requests and watching %s...\n' "$log"
  grew=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -o /dev/null --max-time 5 "$url" 2>/dev/null || true
    sleep 2
    now="$(lab_as_root stat -c '%s' "$log" 2>/dev/null || echo 0)"
    if (( now > size_after_rotate )); then grew=1; break; fi
  done
  if (( grew == 1 )); then
    assert_pass "the application writes to the new file after the rotation"
  else
    assert_fail "the application writes to the new file after the rotation" \
      "${log} has not grown in 20s of requests. The rotation renamed the file; the process still holds the old one. Either signal it to reopen (postrotate, systemctl kill -s USR1) or use copytruncate. Look at: sudo ls -l /proc/\$(pgrep -f gunicorn | head -1)/fd/"
  fi
  printf '      (it was %s bytes before the rotation, %s just after)\n' \
    "$size_before" "$size_after_rotate"
fi

# --- 4b. and the compression, which has to come after the writing ----------
# Order matters here and it took a false failure to notice. delaycompress
# leaves the NEWEST rotation uncompressed on purpose, so a single rotation can
# never show compression under it and a second one is needed. But a second
# rotation forced while the new log is still empty does nothing at all, because
# `notifempty` — which every sensible rule carries — skips an empty file. So
# the second rotation goes here, after the requests above have refilled the
# log, rather than next to the first one where it reads more naturally.
if lab_as_root grep -qE '^\s*delaycompress\b' "$conf"; then
  printf 'delaycompress is set, so forcing a second rotation...\n'
  lab_as_root logrotate --force "$conf" >/dev/null 2>&1 || true
  sleep 2
fi

# Decompressed, not inferred from the suffix: a file named .gz that is not gzip
# is exactly the kind of thing a suffix check blesses.
compressed=''
for cand in $(lab_as_root find "$logdir" -maxdepth 1 \
                \( -name "${base}*.gz" -o -name "${base}*.xz" -o -name "${base}*.zst" \) \
                -print 2>/dev/null | sort); do
  compressed="$cand"; break
done
if [[ -z "$compressed" ]]; then
  assert_fail "a rotation is really compressed" \
    "no .gz, .xz or .zst alongside ${log} after rotating. Is 'compress' in the rule, and does this logrotate have the compressor it names?"
else
  case "$compressed" in
    *.gz)  assert_cmd "the rotation really is gzip ($(basename "$compressed") decompresses)" \
             lab_as_root gzip -t "$compressed" ;;
    *.xz)  assert_cmd "the rotation really is xz ($(basename "$compressed") decompresses)" \
             lab_as_root xz -t "$compressed" ;;
    *.zst) assert_cmd "the rotation really is zstd ($(basename "$compressed") decompresses)" \
             lab_as_root zstd -t "$compressed" ;;
  esac
fi

# --- 5. nothing is left holding a deleted copy ------------------------------
# An absence claim, so it carries a control: a file in this log's own directory
# is created, opened, unlinked, and the detector is required to find it before
# the absence of anything else is believed.
detect_deleted() {
  local fd target
  for fd in /proc/[0-9]*/fd/*; do
    target="$(readlink "$fd" 2>/dev/null || true)"
    [[ -n "$target" ]] || continue
    [[ "$target" == *"(deleted)"* ]] || continue
    [[ "$target" == "${log}"* ]] || continue
    return 0
  done
  return 1
}
plant_deleted() {
  lab_as_root sh -c "printf 'control\n' > '$control'"
  setsid bash -c "exec 9< '$control'; rm -f '$control' 2>/dev/null ||
                  sudo rm -f '$control'; sleep 45" >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$control_pid"
  sleep 3
}
clean_deleted() {
  [[ -s "$control_pid" ]] || return 0
  pkill -P "$(cat "$control_pid")" 2>/dev/null || true
  kill "$(cat "$control_pid")" 2>/dev/null || true
  sleep 2
  lab_as_root rm -f "$control" 2>/dev/null || true
  rm -f "$control_pid"
}
assert_absent "no process is left holding a deleted copy of the log" \
  detect_deleted plant_deleted clean_deleted

assert_summary
