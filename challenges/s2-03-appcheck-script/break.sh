#!/usr/bin/env bash
# s2-03 — a mission: nothing is broken. This says where the script goes, what
# the three URLs are, and what the check will do to it — including that it will
# stop an application, which is worth knowing before it happens.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-03-appcheck-script'
script="${S2_BIN_DIR:-/usr/local/bin}/appcheck.sh"
stop_app="${S2_03_STOP_APP:-leaves}"

printf 'Nothing is broken: this is a mission.\n\n'
printf 'Write it here, and make it executable:\n  %s\n\n' "$script"

if [[ -e "$script" ]]; then
  printf 'Something is already there (%s bytes). Not touched.\n\n' \
    "$(stat -c '%s' "$script")"
fi

printf 'The three applications, from lab.conf:\n'
printf '  %-8s %s\n' stages "${STAGES_URL:-<STAGES_URL unset>}"
printf '  %-8s %s\n' leaves "${LEAVES_URL:-<LEAVES_URL unset>}"
printf '  %-8s %s\n' nurse  "${NURSE_API:-<NURSE_API unset>}"

printf '\nAnd what they answer right now:\n'
for pair in "stages:${STAGES_URL:-}" "leaves:${LEAVES_URL:-}" "nurse:${NURSE_API:-}"; do
  name="${pair%%:*}"; url="${pair#*:}"
  if [[ -z "$url" ]]; then
    printf '  %-8s no URL in lab.conf\n' "$name"
    continue
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
  printf '  %-8s %s\n' "$name" "${code:-no response}"
done

printf '\nThresholds the check will override to force the warning paths:\n'
printf '  APPCHECK_DISK_PCT=0            must produce a disk WARN\n'
printf '  APPCHECK_MEM_MIN_MB=<huge>     must produce a memory WARN\n'
printf 'Read them from the environment with defaults of 80 and 256.\n'

printf '\nThe check will STOP %s to prove the failure path, and start it again\n' "$stop_app"
printf 'afterwards whatever the result. Nothing else is touched.\n'

printf '\nWhen it works:\n  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
