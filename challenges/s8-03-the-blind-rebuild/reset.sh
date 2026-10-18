#!/usr/bin/env bash
# s8-03 — reset: nothing to undo, and emphatically nothing to undo in the
# runbooks. The commits made during the rebuild are the one thing this
# challenge produced; a reset that removed them would delete the work and keep
# the exercise, which is exactly backwards.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard

ID='s8-03-the-blind-rebuild'
rm -f "$(lab_state_dir "$ID")/armed"
lab_state_set "$ID" BUILD_STARTED_AT 0

cat <<'TXT'
Cleared: the arming state and the clock. Your runbooks were not touched, and
will not be by anything in this repository — the commits you made while stuck
are the output of the exercise, not scaffolding for it.

The recorded baseline is kept, so you can still run the check with --since.
To make the attempt again: commit the runbooks, a new bare image, then
  lab start s8-03-the-blind-rebuild
which records a fresh baseline at that point.
TXT
lab_state_set "$ID" BROKEN_AT 0
