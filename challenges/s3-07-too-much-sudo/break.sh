#!/usr/bin/env bash
# s3-07 — break: dev1 is granted unrestricted passwordless sudo.
#
# The account is created with no password and no key, so it cannot be used to
# log in remotely, and nothing about SSH is touched.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s3-07-too-much-sudo'
user="${DEV_USER:-dev1}"
drop="/etc/sudoers.d/${user}"

if ! id -u "$user" >/dev/null 2>&1; then
  lab_as_root useradd --create-home --shell /bin/bash --password '!' "$user"
  lab_state_set "$ID" CREATED_USER 1
fi

[[ ! -f "$drop" ]] || lab_backup_file "$ID" "$drop"

# Written via a temporary file and validated before being put in place: a
# malformed sudoers file locks everyone out, which would be a trick, not a lesson.
tmp="$(mktemp)"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" >"$tmp"
if lab_as_root visudo -c -q -f "$tmp" >/dev/null 2>&1; then
  lab_as_root install -m 0440 -o root -g root "$tmp" "$drop"
else
  printf 'refusing: generated sudoers file did not validate\n' >&2
  rm -f "$tmp"; exit 1
fi
rm -f "$tmp"

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
