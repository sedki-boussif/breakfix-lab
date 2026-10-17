#!/usr/bin/env bash
# s3-02 — break: DATABASE_URL points at a port nothing listens on, so every
# query fails and the catalogue renders empty. No data is touched.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-02-theses-api-down'
env_file="${NURSE_ENV:?set NURSE_ENV in lab.conf}"
[[ -f "$env_file" ]] || { printf 'no environment file at %s\n' "$env_file" >&2; exit 1; }

lab_backup_file "$ID" "$env_file"
# Only rewrite a URL that still names the right port, so a second run is a no-op.
if grep -qE '^DATABASE_URL=.*:5432/' "$env_file"; then
  lab_as_root sed -i -E 's|^(DATABASE_URL=.*):5432/|\1:5433/|' "$env_file"
fi

# Make the service read the file again. Under systemd a restart re-reads the
# EnvironmentFile; under compose the environment is fixed when the container is
# created, so a plain restart would keep the old value and hide the fault.
if [[ "$(svc_mode nurse)" == "compose" ]]; then
  svc_compose nurse up -d --force-recreate "$(svc_name nurse api)" >/dev/null 2>&1 || true
else
  svc_restart nurse api >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
