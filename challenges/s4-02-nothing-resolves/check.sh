#!/usr/bin/env bash
# s4-02 — check: names resolve, the apps still reach their database by name,
# and the fix survives a resolver restart — which an edit to /etc/resolv.conf
# on a resolved-managed host does not.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

# A name the lab itself owns, so this does not depend on the internet.
own="${STAGES_VHOST:-stages.lab.invalid}"
assert_cmd "a name from /etc/hosts resolves" getent hosts "$own"

# And a real lookup, which is what actually broke.
# shellcheck disable=SC2016  # the quoted body is not for this shell to expand
assert_cmd "an external name resolves" \
  bash -c 'getent hosts deb.debian.org >/dev/null || dig +short +time=3 +tries=1 deb.debian.org | grep -q .'

# The stand-in reaches its database by name from inside its own network. A
# resolver fix that breaks container DNS is a new fault, not a fix.
# shellcheck disable=SC2016  # the body runs in another shell, with its own $1/$2
assert_cmd "the stand-in can still reach its database by name (${DB_HOSTNAME:-db})" \
  bash -c 'cd "$1" && docker compose exec -T api python -c "import socket,sys; socket.getaddrinfo(sys.argv[1], 5432)" "$2"' \
  _ "${STAGES_DIR:?}" "${DB_HOSTNAME:-db}"

assert_http "stages still answers" "${STAGES_URL:?}" 200

# The part that refuses the shortcut: restart the resolver and ask again. An
# edit to /etc/resolv.conf on a resolved-managed host is reverted here.
if [[ -d /run/systemd/resolve ]]; then
  lab_as_root systemctl restart systemd-resolved >/dev/null 2>&1 || true
  sleep 3
  # shellcheck disable=SC2016  # the quoted body is not for this shell to expand
  assert_eventually "names still resolve after restarting systemd-resolved" 30 \
    bash -c 'getent hosts deb.debian.org >/dev/null || dig +short +time=3 +tries=1 deb.debian.org | grep -q .'
else
  printf 'SKIP  systemd-resolved is not managing this host, so persistence was not re-tested\n'
fi

assert_summary
