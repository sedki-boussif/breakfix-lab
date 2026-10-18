#!/usr/bin/env bash
# s6-03 — reset: undo what the check disturbs if it was interrupted before its
# trap ran, and say where the certificate copy is. What the user built is left
# alone.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"

ID='s6-03-monitoring-first'
cert="${TLS_CERT:-/etc/nginx/tls/lab.crt}"
unit="${S6_03_STOP_UNIT:-${LEAVES_WEB_UNIT:-leaves.service}}"
fsname="${S6_03_DISK_FS:-monitor}"
state="$(lab_state_dir "$ID")"
backup="$state/tls-cert-backup"

# The certificate, if a run was killed between the swap and the restore.
if [[ -s "$backup" ]] && lab_as_root test -f "$cert"; then
  end="$(lab_as_root openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  days=0
  [[ -z "$end" ]] || days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
  if (( days < 14 )); then
    lab_as_root cp -a "$backup" "$cert"
    lab_as_root systemctl reload "${NGINX_UNIT:-nginx.service}" >/dev/null 2>&1 || true
    printf 'Restored your certificate from %s (the installed one had %s days left).\n' \
      "$backup" "$days"
  else
    printf 'Certificate at %s has %s days left; left alone.\n' "$cert" "$days"
  fi
fi

lab_as_root systemctl start "$unit" >/dev/null 2>&1 || true
printf 'Started %s, in case a check was interrupted while it was stopped.\n' "$unit"

if lab_fs_is_ours "$(lab_fs_mnt "$fsname")" 2>/dev/null; then
  lab_fs_destroy "$fsname" >/dev/null 2>&1 || true
  printf 'Removed the test filesystem "%s".\n' "$fsname"
fi

printf '\nYour monitoring and its rules were left alone — they are the work.\n'
printf 'The alert log is kept too: %s\n' "${S6_03_ALERT_LOG:-/var/log/lab-monitor-alerts.log}"
printf 'Truncate it yourself if you want a clean run:  sudo truncate -s 0 %s\n' \
  "${S6_03_ALERT_LOG:-/var/log/lab-monitor-alerts.log}"
lab_state_set "$ID" BROKEN_AT 0
