#!/usr/bin/env bash
# s6-02 — check: the project is shaped properly, it serves where it used to,
# the old unit cannot come back, and the data survives the containers being
# destroyed.
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

ID='s6-02-containerise-leaves'
dir="${LEAVES_DIR:?LEAVES_DIR is not set in lab.conf}"
project="${LEAVES_PROJECT:-leaves}"
unit="${LEAVES_WEB_UNIT:-leaves.service}"
url="${LEAVES_URL:?}"
port="${LEAVES_PORT:-8081}"
db_svc="${DB_SERVICE:-db}"
db="${LEAVES_DB_NAME:-leaves}"
role="${LEAVES_DB_ROLE:-leaves_app}"
table="${LEAVES_COUNT_TABLE:-leave_management_leaverequest}"

# The compose SERVICE name, from lab.conf, not the app's name: leaves runs as
# a single Django service and lab.conf calls it LEAVES_WEB.
app_svc="${LEAVES_WEB:-web}"
compose_shape_assertions "$dir" "$project" "$db_svc" "$app_svc" "$port"

# --- it runs where it used to, and the old unit cannot come back ------------
assert_http "it answers on the URL it always did" "$url" 200

if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
  assert_not "the systemd unit is stopped" systemctl is-active --quiet "$unit"
  assert_not "the systemd unit is disabled, so a reboot cannot restart it" \
    systemctl is-enabled --quiet "$unit"
else
  assert_pass "the systemd unit is gone entirely"
fi

# --- lab.conf agrees, so the rest of the catalogue still works -------------
mode="${LEAVES_MODE:-${RUN_MODE:-}}"
assert_equal "LEAVES_MODE is compose in lab.conf" "$mode" "compose"
if [[ "$mode" == compose ]]; then
  assert_cmd "the lab's own service abstraction works through it" \
    svc_is_active leaves web
fi

# --- and the data survived the move ---------------------------------------
rows_before_move="$(lab_state_get "$ID" ROWS_BEFORE 0)"
live="$(compose_count_rows "$dir" "$db_svc" "$role" "$db" "$table")"
if [[ -z "$live" ]]; then
  assert_fail "the containerised database can be counted" \
    "no answer from ${table} in ${db} — docker compose -p ${project} exec ${db_svc} psql -U ${role} -d ${db} -c '\\dt'"
  assert_summary
  exit $?
fi
# Not zero: a stack that comes back empty every time is consistent and
# worthless, and the survival test below cannot tell those apart.
assert_above "the containerised database holds data at all" "$live" 0 " rows"
if [[ "$rows_before_move" != 0 ]]; then
  assert_equal "the row count matches what the host database held (${rows_before_move})" \
    "$live" "$rows_before_move"
else
  printf 'SKIP  no pre-move row count recorded, so the migration cannot be compared\n'
fi

compose_survives_destruction "$dir" "$project" "$db_svc" "$role" "$db" "$table" "$url"

assert_summary
