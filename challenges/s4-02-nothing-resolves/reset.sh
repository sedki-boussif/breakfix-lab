#!/usr/bin/env bash
# s4-02 — reset: restore the resolver configuration.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-02-nothing-resolves'
target="$(lab_state_get "$ID" TARGET '')"
[[ -z "$target" ]] || lab_restore_file "$ID" "$target"
lab_as_root systemctl restart systemd-resolved >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
