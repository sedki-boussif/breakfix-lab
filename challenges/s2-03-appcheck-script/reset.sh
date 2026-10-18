#!/usr/bin/env bash
# s2-03 — reset: clears the captured runs, and makes sure the application the
# check stops is running. The check restores it from an EXIT trap, so this
# should be a no-op — "should be" is why it is here.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s2-03-appcheck-script'
script="${S2_BIN_DIR:-/usr/local/bin}/appcheck.sh"
stop_app="${S2_03_STOP_APP:-leaves}"
state="$(lab_state_dir "$ID")"

rm -f "$state/run-healthy" "$state/run-failing" "$state/run-warned"
printf 'Cleared: the captured runs from the last check.\n'

svc_start "$stop_app" web >/dev/null 2>&1 || true
svc_start "$stop_app" api >/dev/null 2>&1 || true
printf 'Started %s, in case a check was interrupted before its trap ran.\n' "$stop_app"

if [[ -e "$script" ]]; then
  printf '\n%s was left alone — it is your work, not the lab'"'"'s.\n' "$script"
fi
lab_state_set "$ID" BROKEN_AT 0
