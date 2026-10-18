#!/usr/bin/env bash
# s6-07 — a mission: nothing is broken. This records the row count before the
# move and names the two things this app does that leaves does not — a
# build-time frontend variable, and seven other challenges reading its config.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-07-containerise-nurse'
db="${NURSE_DB_NAME:-nurse}"
table="${NURSE_COUNT_TABLE:-theses_thesis}"
dir="${NURSE_DIR:-/opt/nurse}"
unit="${NURSE_API_UNIT:-nurse-api.service}"

printf 'Nothing is broken: this is a mission.\n\n'

before="$(lab_as_root runuser -u postgres -- psql -tAq -d "$db" \
  -c "SELECT count(*) FROM ${table}" 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "$before" ]]; then
  printf 'Could not count %s in the host database %s.\n' "$table" "$db" >&2
  printf 'Check NURSE_COUNT_TABLE and NURSE_DB_NAME in lab.conf against:\n' >&2
  printf '  sudo -u postgres psql -d %s -c "\\dt"\n' "$db" >&2
  exit 1
fi
lab_state_set "$ID" ROWS_BEFORE "$before"
printf 'Recorded: %s holds %s rows in the host database.\n\n' "$table" "$before"

printf 'Where it runs now:\n'
printf '  api unit: %s (%s, %s)\n' "$unit" \
  "$(systemctl is-active "$unit" 2>/dev/null || echo inactive)" \
  "$(systemctl is-enabled "$unit" 2>/dev/null || echo disabled)"
printf '  api:      127.0.0.1:8000, %s\n' "${NURSE_API:-}"
printf '  frontend: 127.0.0.1:3000, static files served by the host nginx\n'
printf '  env:      %s\n' "${NURSE_ENV:-/etc/nurse/nurse.env}"
printf '  wsgi:     %s\n' "${NURSE_WSGI:-config.wsgi:application}"

printf '\nTwo things this app does that leaves does not:\n\n'
printf '  1. VITE_API_URL is read when the frontend is BUILT, not when it runs.\n'
printf '     In a container that means a build: argument. Set it as an\n'
printf '     environment variable on the running service instead and the page\n'
printf '     loads, looks perfect, and shows an empty list while the API\n'
printf '     reports itself healthy. That is s3-02 by accident.\n\n'
printf '  2. Seven challenges already read this app through lab.conf:\n'
for c in "$LAB_ROOT"/challenges/*/meta; do
  grep -q '^APPS=.*nurse' "$c" || continue
  printf '       %s\n' "$(basename "$(dirname "$c")")"
done
printf '     They find the environment file at NURSE_ENV. If that still points\n'
printf '     at %s after the move, the ones that\n' "${NURSE_ENV:-/etc/nurse/nurse.env}"
printf '     edit it will appear to do nothing at all.\n'

printf '\nDump first:\n'
printf '  sudo -u postgres pg_dump -Fc %s > /var/tmp/%s-before-s6-07.dump\n' "$db" "$db"
printf '\nThen build the project in %s, and when both ports answer:\n' "$dir"
printf '  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
