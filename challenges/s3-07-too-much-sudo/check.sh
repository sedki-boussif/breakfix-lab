#!/usr/bin/env bash
# s3-07 — check: exactly one permitted command, it is the one the account was
# granted for, and nothing else can be restarted with it.
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
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

user="${DEV_USER:-dev1}"
other_unit="${DB_UNIT:-postgresql.service}"

assert_cmd "the account still exists" id -u "$user"
assert_cmd "sudoers is valid" lab_as_root visudo -c -q

# sudo's own view is the only authority: it accounts for group membership,
# drop-in files and defaults together.
listing="$(lab_as_root sudo -l -U "$user" 2>/dev/null || true)"
permitted="$(sed -n '/may run the following/,$p' <<<"$listing" \
             | grep -vE 'may run the following|^\s*$' | sed 's/^[[:space:]]*//' || true)"
count="$(grep -c . <<<"$permitted" || true)"

if [[ "$count" == "1" ]]; then
  assert_pass "sudo -l lists exactly one permitted command"
else
  assert_fail "sudo -l lists exactly one permitted command" \
    "it lists ${count}: $(tr '\n' '; ' <<<"$permitted")"
fi

if grep -qE '\(ALL(:ALL)?\)[[:space:]]*(NOPASSWD:[[:space:]]*)?ALL$' <<<"$permitted"; then
  assert_fail "the grant is not ALL" \
    "the account may still run everything — check group membership as well as /etc/sudoers.d"
else
  assert_pass "the grant is not ALL"
fi

if grep -qE 'systemctl[[:space:]]*(\*)?$' <<<"$permitted"; then
  assert_fail "the grant names its arguments" \
    "a bare systemctl grant allows stop, mask and any unit — including ssh. Name the command: /usr/bin/systemctl restart nginx"
else
  assert_pass "the grant names its arguments"
fi

# Both halves of the remediation, tested as the account itself.
assert_cmd "${user} can still restart nginx" \
  lab_as_root runuser -u "$user" -- sudo -n systemctl restart nginx
assert_not "${user} cannot restart ${other_unit}" \
  lab_as_root runuser -u "$user" -- sudo -n systemctl restart "$other_unit"
assert_not "${user} cannot get a root shell" \
  lab_as_root runuser -u "$user" -- sudo -n /bin/bash -c 'id -u'

assert_cmd "nginx is running after the test" systemctl is-active --quiet nginx

assert_summary
