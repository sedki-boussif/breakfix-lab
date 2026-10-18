#!/usr/bin/env bash
# s4-02 — break: point the resolver at an address that does not answer.
# Connectivity is untouched, so everything that uses an IP keeps working.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-02-nothing-resolves'
# RFC 5737 documentation space: routable nowhere, answers nothing, and can
# never belong to anyone.
bogus='192.0.2.53'

if [[ -d /run/systemd/resolve ]] && command -v resolvectl >/dev/null 2>&1; then
  conf="${RESOLVED_CONF:-/etc/systemd/resolved.conf}"
  lab_backup_file "$ID" "$conf"
  if ! grep -qE "^DNS=${bogus}" "$conf" 2>/dev/null; then
    lab_as_root sed -i -e 's/^#\?DNS=.*/DNS='"$bogus"'/' \
                       -e 's/^#\?FallbackDNS=.*/FallbackDNS=/' "$conf"
    grep -qE '^DNS=' "$conf" || printf 'DNS=%s\n' "$bogus" | lab_as_root tee -a "$conf" >/dev/null
  fi
  lab_as_root systemctl restart systemd-resolved >/dev/null 2>&1 || true
  lab_state_set "$ID" TARGET "$conf"
else
  conf="${RESOLV_CONF:-/etc/resolv.conf}"
  lab_backup_file "$ID" "$conf"
  printf 'nameserver %s\n' "$bogus" | lab_as_root tee "$conf" >/dev/null
  lab_state_set "$ID" TARGET "$conf"
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
