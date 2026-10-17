#!/usr/bin/env bash
# s3-02 — reset: restore the environment file and recreate the api service.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-02-theses-api-down'
lab_restore_file "$ID" "${NURSE_ENV:?}"
svc_compose nurse up -d --force-recreate "$(svc_name nurse api)" >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
