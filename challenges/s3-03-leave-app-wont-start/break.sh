#!/usr/bin/env bash
# s3-03 — break: SECRET_KEY disappears from the environment file. The app has no
# default for it, so Django raises at import. Repeated restarts also drive the
# unit into its start limit, exactly as a panicking colleague would.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-03-leave-app-wont-start'
env_file="${LEAVES_ENV:?set LEAVES_ENV in lab.conf}"
[[ -f "$env_file" ]] || { printf 'no environment file at %s\n' "$env_file" >&2; exit 1; }

lab_backup_file "$ID" "$env_file"
if grep -q '^SECRET_KEY=' "$env_file"; then
  lab_as_root sed -i '/^SECRET_KEY=/d' "$env_file"
fi

# Three failed starts, which is how the unit ends up refusing to start at all.
for _ in 1 2 3; do
  svc_restart leaves web >/dev/null 2>&1 || true
done

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
