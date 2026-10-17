#!/usr/bin/env bash
# s5-08 — break: an invalid nginx directive stops nginx starting, and the
# database is stopped behind it. The second fault is unobservable until the
# first is fixed.
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

ID='s5-08-two-things-at-once'
site="${NGINX_SITE:?set NGINX_SITE in lab.conf}"
db_unit="${DB_UNIT:-postgresql.service}"
marker='# lab s5-08'

[[ -f "$site" ]] || { printf 'no nginx site file at %s\n' "$site" >&2; exit 1; }
lab_backup_file "$ID" "$site"

# Fault one: a directive that does not exist. nginx -t names the file and line.
if ! grep -qF "$marker" "$site"; then
  printf '\nproxy_read_timout 60s;   %s\n' "$marker" | lab_as_root tee -a "$site" >/dev/null
fi
# Restart rather than reload: a reload would fail and leave the old config
# serving, which is a different (and quieter) fault.
lab_as_root systemctl restart nginx >/dev/null 2>&1 || true

# Fault two, hidden behind fault one.
lab_as_root systemctl stop "$db_unit" >/dev/null 2>&1 || true

lab_state_set "$ID" SITE "$site"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
