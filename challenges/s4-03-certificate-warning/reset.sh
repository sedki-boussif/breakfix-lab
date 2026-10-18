#!/usr/bin/env bash
# s4-03 — reset: put the original certificate back.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-03-certificate-warning'
lab_restore_file "$ID" "${TLS_CERT:?}"
lab_restore_file "$ID" "${TLS_KEY:?}"
if lab_as_root nginx -t >/dev/null 2>&1; then
  lab_as_root systemctl reload nginx >/dev/null 2>&1 || true
fi
lab_state_set "$ID" BROKEN_AT 0
