#!/usr/bin/env bash
# s2-04 — a mission: nothing is broken. This makes sure there is a log to
# rotate and shows how big it is, because a rotation mission against an empty
# file proves nothing.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-04-rotate-the-logs'
log="${LEAVES_LOG:-/var/log/leaves/access.log}"
conf="${S2_04_LOGROTATE_CONF:-/etc/logrotate.d/leaves}"
keep="${S2_04_KEEP:-7}"
url="${LEAVES_URL:-}"

printf 'Nothing is broken: this is a mission.\n\n'

printf 'The log:  %s\n' "$log"
if lab_as_root test -e "$log"; then
  printf '  size:   %s\n' "$(lab_as_root du -h "$log" | cut -f1)"
  printf '  lines:  %s\n' "$(lab_as_root wc -l <"$log")"
  printf '  owner:  %s\n' "$(lab_as_root stat -c '%U:%G %a' "$log")"
else
  printf '  it does not exist yet.\n\n'
  printf 'SETUP.md section 6 points the leaves access log here on purpose — not\n'
  printf 'at the journal, which cannot be rotated and would make this mission\n'
  printf 'vacuous. Configure it, make a few requests, then start this again.\n'
fi

printf '\nThe rule goes here: %s\n' "$conf"
if lab_as_root test -e "$conf"; then
  printf 'Something is already there. Not touched:\n'
  lab_as_root sed 's/^/  | /' "$conf"
fi

printf '\nWhat is already rotating on this machine, for reference:\n'
lab_as_root ls -1 /etc/logrotate.d/ 2>/dev/null | sed 's/^/  /' | head -12

printf '\nAnd what the state file knows, which is how logrotate decides whether\n'
printf 'a day has passed:\n'
if lab_as_root test -e /var/lib/logrotate/status; then
  printf '  /var/lib/logrotate/status, %s entries\n' \
    "$(lab_as_root grep -c . /var/lib/logrotate/status || echo 0)"
else
  printf '  no /var/lib/logrotate/status yet\n'
fi

printf '\nThe check will force a rotation, then make a request to %s and watch\n' \
  "${url:-the leaves URL}"
printf 'whether the NEW file grows. That is the assertion that catches a rule\n'
printf 'which rotates correctly and leaves the application writing to a file\n'
printf 'with no name any more.\n'

printf '\nDaily, rotate %s, compressed. When it works:\n  lab check %s\n' "$keep" "$ID"
lab_state_set "$ID" BROKEN_AT 0
