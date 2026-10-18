#!/usr/bin/env bash
# s6-03 — a mission: nothing is broken. This says what the check will do to the
# machine, because it is more invasive than any other mission in the catalogue
# and finding that out afterwards would be unreasonable.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-03-monitoring-first'
alog="${S6_03_ALERT_LOG:-/var/log/lab-monitor-alerts.log}"
cert="${TLS_CERT:-/etc/nginx/tls/lab.crt}"
unit="${S6_03_STOP_UNIT:-${LEAVES_WEB_UNIT:-leaves.service}}"
fsname="${S6_03_DISK_FS:-monitor}"

printf 'Nothing is broken: this is a mission.\n\n'
printf 'Three alerts to build: a filesystem over 80%%, a service down, and a\n'
printf 'certificate with under 14 days left.\n\n'

printf 'Where the check will look for them:\n  %s\n' "$alog"
if lab_as_root test -e "$alog"; then
  printf '  exists, %s lines\n' "$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
else
  printf '  does not exist yet — whatever you build has to create and append to it\n'
fi
printf '\nReload command (S6_03_RELOAD): %s\n' "${S6_03_RELOAD:-<none set>}"

printf '\nWhat the check will do to this machine, and undo:\n'
printf '  1. create a %sMB loopback filesystem named "%s" and fill it past 80%%\n' \
  "${S6_03_DISK_MB:-512}" "$fsname"
printf '     — a filesystem your monitoring has never seen, which is the point\n'
printf '  2. stop %s, then start it again\n' "$unit"
printf '  3. replace %s with a certificate expiring in\n' "$cert"
printf '     seven days, then put yours back from a copy it takes first\n'
printf '\nAll three are restored on every exit path, including a failed one.\n'

printf '\nCurrent state of the three things it will disturb:\n'
printf '  %s\n' "$(df -h / | tail -1)"
printf '  %s: %s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || echo inactive)"
if lab_as_root test -f "$cert"; then
  end="$(lab_as_root openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$end" ]]; then
    printf '  %s expires %s (%s days)\n' "$cert" "$end" \
      "$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))"
  fi
else
  printf '  %s does not exist — SETUP.md section 8 makes it\n' "$cert"
fi

printf '\nBuild it, then:\n  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
