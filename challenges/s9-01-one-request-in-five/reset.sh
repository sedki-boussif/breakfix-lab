#!/usr/bin/env bash
# s9-01 — reset: remove the upstream and put the vhost back.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s9-01-one-request-in-five'
lab_as_root rm -f "$(lab_state_get "$ID" SNIPPET '/etc/nginx/conf.d/lab-s9-01-upstream.conf')"
lab_restore_file "$ID" "${NGINX_SITE:?}"
if lab_as_root nginx -t >/dev/null 2>&1; then
  lab_as_root systemctl reload nginx >/dev/null 2>&1 || true
fi
lab_state_set "$ID" BROKEN_AT 0
