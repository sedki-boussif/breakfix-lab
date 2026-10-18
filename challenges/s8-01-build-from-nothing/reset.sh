#!/usr/bin/env bash
# s8-01 — reset: nothing to undo. A mission that built a machine is not
# something a script should unbuild; what this clears is the clock and the
# arming, so the attempt can be made again from a fresh image.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard

ID='s8-01-build-from-nothing'
state="$(lab_state_dir "$ID")"
rm -f "$state/armed"
lab_state_set "$ID" BUILD_STARTED_AT 0

cat <<'TXT'
Cleared: the build clock and the arming state. Nothing on the machine was
touched — unbuilding a server you just built is not a thing a reset script
should do, and the point of the mission is the next bare image anyway.

To make the attempt again properly: a new Ubuntu 24.04 image, then
  lab start s8-01-build-from-nothing
TXT
lab_state_set "$ID" BROKEN_AT 0
