#!/usr/bin/env bash
# s5-08 — reset: valid config, nginx up, database up.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s5-08-two-things-at-once'
site="${NGINX_SITE:?}"
db_unit="${DB_UNIT:-postgresql.service}"

lab_restore_file "$ID" "$site"
if grep -qF '# lab s5-08' "$site" 2>/dev/null; then
  lab_as_root sed -i '/# lab s5-08/d' "$site"
fi
lab_as_root systemctl reset-failed nginx "$db_unit" >/dev/null 2>&1 || true
lab_as_root systemctl start "$db_unit" >/dev/null 2>&1 || true
lab_as_root systemctl restart nginx >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
