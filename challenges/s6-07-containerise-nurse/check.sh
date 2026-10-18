#!/usr/bin/env bash
# s6-07 — check: s6-02's standard, plus the three things that make nurse the
# harder one — two ports, a build-time frontend variable, and seven other
# challenges that read this app's configuration through lab.conf.
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
# shellcheck source=lib/compose.sh
. "$LAB_ROOT/lib/compose.sh"

ID='s6-07-containerise-nurse'
dir="${NURSE_DIR:?NURSE_DIR is not set in lab.conf}"
project="${NURSE_PROJECT:-nurse}"
api_svc="${NURSE_API_SVC:-api}"
web_svc="${NURSE_WEB_SVC:-web}"
unit="${NURSE_API_UNIT:-nurse-api.service}"
api_url="${NURSE_API:?}"
list_url="${NURSE_LIST:?}"
web_url="${NURSE_WEB:-http://127.0.0.1:3000/}"
db_svc="${DB_SERVICE:-db}"
db="${NURSE_DB_NAME:-nurse}"
role="${NURSE_DB_ROLE:-nurse_app}"
table="${NURSE_COUNT_TABLE:-theses_thesis}"
env_path="${NURSE_ENV:-}"

# The shared standard, against the API service.
compose_shape_assertions "$dir" "$project" "$db_svc" "$api_svc" 8000
# And the second port, which is what makes this one different.
compose_publishes_loopback "$dir" "$web_svc" 3000

# --- both tiers answer where they used to ----------------------------------
assert_http "the API answers on the URL it always did" "$api_url" 200
assert_http "the frontend answers on the URL it always did" "$web_url" 200

# A healthy API and a working list are different claims, which is the whole of
# s3-02: the health endpoint can be green while the list is empty because the
# frontend was built pointing somewhere else.
assert_http "the list endpoint answers" "$list_url" 200
assert_http_body "the list endpoint returns rows, not an empty list" \
  "$list_url" '"(id|title|count)"|\[[[:space:]]*\{'

# --- the build-time variable, which is the trap ----------------------------
# Asserted against the raw file rather than the resolved config: what matters
# is that VITE_API_URL is a build argument, and `config` shows an environment
# variable and a build arg in different places precisely so this is checkable.
# compose_q takes the filter SECOND and passes anything after it to jq. The
# first version of these two had --arg in the filter slot, which made both
# queries return nothing and the assertion report "neither", regardless.
# shellcheck disable=SC2016  # jq filter: $w is jq's variable, not the shell's
vite_build="$(compose_q "$dir" \
  '.services[$w].build.args // {} | has("VITE_API_URL")' --arg w "$web_svc")"
# shellcheck disable=SC2016  # jq filter: $w is jq's variable, not the shell's
vite_env="$(compose_q "$dir" \
  '.services[$w].environment // {} | has("VITE_API_URL")' --arg w "$web_svc")"
if [[ "$vite_build" == true ]]; then
  assert_pass "VITE_API_URL is a build argument"
elif [[ "$vite_env" == true ]]; then
  assert_fail "VITE_API_URL is a build argument" \
    "it is an environment variable on the running ${web_svc} service, which does nothing: the value is baked into the bundle at build time. The page will load, look perfect, and show an empty list — s3-02's exact shape, caused by accident"
else
  assert_fail "VITE_API_URL is a build argument" \
    "it is neither a build arg nor an environment variable on ${web_svc}. If the frontend happens to work, it is because a default was compiled in, and it will stop working the moment the API moves"
fi

# --- the old unit cannot come back -----------------------------------------
if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
  assert_not "the API's systemd unit is stopped" systemctl is-active --quiet "$unit"
  assert_not "the API's systemd unit is disabled" systemctl is-enabled --quiet "$unit"
else
  assert_pass "the API's systemd unit is gone entirely"
fi

# --- lab.conf tells the rest of the catalogue the truth --------------------
mode="${NURSE_MODE:-${RUN_MODE:-}}"
assert_equal "NURSE_MODE is compose in lab.conf" "$mode" "compose"
if [[ "$mode" == compose ]]; then
  assert_cmd "the lab's service abstraction finds the api" svc_is_active nurse api
  assert_cmd "the lab's service abstraction finds the web tier" svc_is_active nurse web
fi

# NURSE_ENV is edited by several challenges to cause faults. If it still names
# the systemd-era file while the app reads the project's own, those challenges
# edit a file nothing loads and appear to do nothing at all — the worst
# possible failure for a training lab, because it looks like the challenge is
# broken rather than the configuration.
if [[ -z "$env_path" ]]; then
  assert_fail "NURSE_ENV is set in lab.conf" \
    "challenges edit this file to cause faults; unset, they have nowhere to write"
elif ! lab_as_root test -f "$env_path"; then
  assert_fail "NURSE_ENV names a file that exists (${env_path})" \
    "it points at the systemd-era path, which the containerised app no longer reads. Point it at the project's env file"
else
  assert_pass "NURSE_ENV names a file that exists (${env_path})"
  # And the project actually loads it, rather than it merely being present.
  if grep -qE "$(basename "$env_path")|env_file" "$dir"/compose.y*ml 2>/dev/null; then
    assert_pass "the compose project loads the file NURSE_ENV names"
  else
    assert_fail "the compose project loads the file NURSE_ENV names" \
      "${env_path} exists but nothing in the compose file references it, so a challenge editing it changes nothing"
  fi
fi

# --- an override file has to work, because s5-04 writes one ---------------
# A positive claim, made by doing it: the file is created, the project is asked
# to re-read its configuration, and the limit has to show up. Anything left
# behind is removed afterwards whichever way it went.
override="$dir/compose.override.yaml"
if lab_as_root test -e "$override"; then
  printf 'SKIP  %s already exists, so the override test would overwrite your work\n' "$override"
else
  lab_as_root tee "$override" >/dev/null <<YML
services:
  ${api_svc}:
    mem_limit: 512m
YML
  # shellcheck disable=SC2016  # jq filter: $a is jq's variable, not the shell's
  got="$(compose_q "$dir" '.services[$a].mem_limit // empty' --arg a "$api_svc")"
  if [[ -n "$got" ]]; then
    assert_pass "an override file is read (s5-04 imposes a memory limit this way)"
  else
    assert_fail "an override file is read" \
      "compose.override.yaml was ignored. s5-04 limits this app's memory through one, and a project that does not pick it up breaks that challenge silently"
  fi
  lab_as_root rm -f "$override"
fi

# --- the restart s3-06 and s5-04 both depend on ---------------------------
assert_cmd "svc_restart nurse api succeeds" svc_restart nurse api
assert_eventually "and the API comes back after it" 90 \
  curl -fsS -o /dev/null --max-time 5 "$api_url"

# --- the data came with it, and survives destruction ----------------------
rows_before_move="$(lab_state_get "$ID" ROWS_BEFORE 0)"
live="$(compose_count_rows "$dir" "$db_svc" "$role" "$db" "$table")"
if [[ -z "$live" ]]; then
  assert_fail "the containerised database can be counted" \
    "no answer from ${table} in ${db} — docker compose -p ${project} exec ${db_svc} psql -U ${role} -d ${db} -c '\\dt'"
  assert_summary
  exit $?
fi
assert_above "the containerised database holds data at all" "$live" 0 " rows"
if [[ "$rows_before_move" != 0 ]]; then
  assert_equal "the row count matches what the host database held (${rows_before_move})" \
    "$live" "$rows_before_move"
else
  printf 'SKIP  no pre-move row count recorded, so the migration cannot be compared\n'
fi

compose_survives_destruction "$dir" "$project" "$db_svc" "$role" "$db" "$table" "$api_url"

assert_summary
