#!/usr/bin/env bash
# s3-07 — reset: remove the grant, and the account if we created it.
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

ID='s3-07-too-much-sudo'
user="${DEV_USER:-dev1}"
drop="/etc/sudoers.d/${user}"

lab_as_root rm -f "$drop"
lab_restore_file "$ID" "$drop"

if [[ "$(lab_state_get "$ID" CREATED_USER 0)" == 1 ]] && id -u "$user" >/dev/null 2>&1; then
  lab_as_root userdel -r "$user" >/dev/null 2>&1 || true
  lab_state_set "$ID" CREATED_USER 0
fi

lab_as_root visudo -c -q >/dev/null 2>&1 || printf 'warning: sudoers does not validate\n' >&2
lab_state_set "$ID" BROKEN_AT 0
