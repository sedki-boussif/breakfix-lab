#!/usr/bin/env bash
# s2-02 — reset: the script is the user's work, so this does not delete it.
# Clearing someone's answer because they asked to start over is defensible;
# doing it silently when they were only resetting state is not.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-02-sysinfo-script'
script="${S2_BIN_DIR:-/usr/local/bin}/sysinfo.sh"
state="$(lab_state_dir "$ID")"
rm -f "$state/output" "$state/output-second-run"

printf 'Cleared: the captured output from the last check.\n'
if [[ -e "$script" ]]; then
  printf '\n%s was left alone — it is your work, not the lab'"'"'s.\n' "$script"
  printf 'To start the script over yourself:\n  sudo rm %s\n' "$script"
fi
lab_state_set "$ID" BROKEN_AT 0
