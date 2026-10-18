#!/usr/bin/env bash
# s8-01 — a mission: nothing is broken. This starts the clock and says what the
# suite will want, because the expensive mistake here is building for three
# hours and discovering at the end that lab.conf never recorded any of it.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s8-01-build-from-nothing'

printf 'Nothing is broken: this is a mission, and the clock starts now.\n\n'

started="$(lab_state_get "$ID" BUILD_STARTED_AT 0)"
if [[ "$started" == 0 ]]; then
  lab_state_set "$ID" BUILD_STARTED_AT "$(date +%s)"
  printf 'Clock started at %s.\n' "$(date '+%F %T')"
else
  printf 'Clock was already running, since %s — not restarted.\n' \
    "$(date -d "@$started" '+%F %T')"
  printf 'To start it again from scratch: lab reset %s\n' "$ID"
fi

printf '\nWhat lab.conf still needs to be filled in before the suite can hold\n'
printf 'you to anything:\n'
missing=0
for var in LAB_ADMIN_USER EXPECTED_PORTS EXPECTED_USERS \
           STAGES_VHOST LEAVES_VHOST NURSE_VHOST TLS_CERT \
           BACKUP_REMOTE BACKUP_PASSWORD_FILE BACKUP_FINGERPRINT \
           BACKUP_MARKER BACKUP_ALERT_LOG BACKUP_TIMER; do
  if [[ -z "${!var:-}" ]]; then
    printf '  %-24s empty\n' "$var"
    missing=$(( missing + 1 ))
  fi
done
(( missing > 0 )) || printf '  nothing — all of them are set\n'

printf '\nWhere this machine is now:\n'
printf '  listening: %s\n' \
  "$(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
printf '  expected:  %s\n' "${EXPECTED_PORTS:-<unset>}"
printf '  accounts:  %s\n' \
  "$(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd | sort | tr '\n' ' ')"

printf '\nBuild it, then:\n'
printf '  lab check %s --arm      # says what is still missing\n' "$ID"
printf '  sudo reboot\n'
printf '  lab check %s            # the full suite\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
