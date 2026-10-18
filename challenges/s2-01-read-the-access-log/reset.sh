#!/usr/bin/env bash
# s2-01 — reset: remove the log and the answer sheet. A regenerated log is
# byte-identical, so the questions have the same answers; what this really
# clears is a half-filled answer sheet.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-01-read-the-access-log'
dir="${S2_01_DIR:-/var/tmp/lab-s2-01}"

# Only ever this directory, and only when it looks like ours: a reset that
# takes an argument from config and removes it recursively deserves a check
# that it is removing what it thinks it is.
if [[ -f "$dir/access.log" || -f "$dir/answers.txt" ]]; then
  rm -rf -- "$dir"
  printf 'Removed %s — the log and the answer sheet.\n' "$dir"
  printf 'lab start %s generates an identical log and a blank sheet.\n' "$ID"
else
  printf 'Nothing to remove: %s holds no lab log or answer sheet.\n' "$dir"
fi
lab_state_set "$ID" BROKEN_AT 0
