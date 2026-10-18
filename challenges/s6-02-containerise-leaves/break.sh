#!/usr/bin/env bash
# s6-02 — a mission: nothing is broken. This records what the data looks like
# before the move, because "the data came with it" is the only assertion in
# this challenge that cannot be reconstructed afterwards.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-02-containerise-leaves'
db="${LEAVES_DB_NAME:-leaves}"
role="${LEAVES_DB_ROLE:-leaves_app}"
table="${LEAVES_COUNT_TABLE:-leave_management_leaverequest}"
dir="${LEAVES_DIR:-/opt/leaves}"
unit="${LEAVES_WEB_UNIT:-leaves.service}"

printf 'Nothing is broken: this is a mission.\n\n'

# The row count now, from the host database, while it is still the only copy.
# runuser rather than `sudo -u`: lab_as_root runs its argument directly when
# already root, and `-u postgres` is then a command that does not exist.
before="$(lab_as_root runuser -u postgres -- psql -tAq -d "$db" \
  -c "SELECT count(*) FROM ${table}" 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "$before" ]]; then
  printf 'Could not count %s in the host database %s.\n' "$table" "$db" >&2
  printf 'Check LEAVES_COUNT_TABLE and LEAVES_DB_NAME in lab.conf against:\n' >&2
  printf '  sudo -u postgres psql -d %s -c "\\dt"\n' "$db" >&2
  exit 1
fi
lab_state_set "$ID" ROWS_BEFORE "$before"
printf 'Recorded: %s holds %s rows in the host database.\n' "$table" "$before"
printf 'That number is what "the data came with it" will be measured against.\n'

printf '\nWhere it runs now:\n'
printf '  unit:     %s (%s, %s)\n' "$unit" \
  "$(systemctl is-active "$unit" 2>/dev/null || echo inactive)" \
  "$(systemctl is-enabled "$unit" 2>/dev/null || echo disabled)"
printf '  database: host PostgreSQL, %s owned by %s\n' "$db" "$role"
printf '  port:     127.0.0.1:%s, proxied by the host nginx\n' "${LEAVES_PORT:-8081}"
printf '  env:      %s\n' "${LEAVES_ENV:-/etc/leaves/leaves.env}"
printf '  wsgi:     %s\n' "${LEAVES_WSGI:-leave_management_project.wsgi:application}"

printf '\nDump the data BEFORE you change anything, and put it somewhere %s\n' "$dir"
printf 'cannot lose:\n'
printf '  sudo -u postgres pg_dump -Fc %s > /var/tmp/%s-before-s6-02.dump\n' "$db" "$db"

printf '\nThen build the project in %s, and when it serves:\n' "$dir"
printf '  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
