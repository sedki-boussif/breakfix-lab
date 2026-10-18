#!/usr/bin/env bash
# s9-01 — break: put the API behind a three-member upstream, one of which
# points at nothing. nginx round-robins, so most requests succeed.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s9-01-one-request-in-five'
site="${NGINX_SITE:?}"
dead_port="${S9_01_DEAD_PORT:-8009}"
api_port="$(printf '%s' "${NURSE_API:-http://127.0.0.1:8000/}" | sed -E 's|.*:([0-9]+).*|\1|')"
snippet='/etc/nginx/conf.d/lab-s9-01-upstream.conf'

[[ -f "$site" ]] || { printf 'no nginx site at %s\n' "$site" >&2; exit 1; }
lab_backup_file "$ID" "$site"

# Three members: two real, one pointing at a port with nothing on it.
lab_as_root tee "$snippet" >/dev/null <<CONF
# Theses API backends
upstream theses_api {
    server 127.0.0.1:${api_port};
    server 127.0.0.1:${api_port};
    server 127.0.0.1:${dead_port};
}
CONF
lab_state_set "$ID" SNIPPET "$snippet"
lab_state_set "$ID" MEMBERS 3

# Point the vhost's /api/ location at the upstream instead of the single host.
#
# proxy_next_upstream is also turned off, and that is not decoration: by
# default nginx silently retries the next member when one refuses a connection,
# so a dead member produces no client-visible failures at all. Found by
# measuring it — thirty requests through a three-member upstream with one dead
# member returned thirty 200s. Turning the retry off is a real configuration
# people choose (it avoids replaying non-idempotent requests) and it is what
# makes this fault reach the user.
if ! grep -q 'theses_api' "$site"; then
  lab_as_root sed -i \
    -e "s|proxy_pass http://127.0.0.1:${api_port};|proxy_pass http://theses_api;\n        proxy_next_upstream off;|" \
    "$site"
fi

if lab_as_root nginx -t >/dev/null 2>&1; then
  lab_as_root systemctl reload nginx >/dev/null 2>&1 || true
else
  printf 'nginx rejected the configuration; backing out\n' >&2
  lab_as_root rm -f "$snippet"
  lab_restore_file "$ID" "$site"
  lab_as_root systemctl reload nginx >/dev/null 2>&1 || true
  exit 1
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
