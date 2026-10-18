#!/usr/bin/env bash
# s7-02 — reset: nothing to undo. Drill artefacts are yours to remove.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
printf 'Nothing to undo: s7-02 is a mission.\n'
printf 'Your drill artefacts, to remove when you are done with them:\n'
printf '  sudo rm -rf /tmp/drill* ; sudo -u postgres dropdb --if-exists stages_drill\n'
lab_state_set 's7-02-restore-drills' BROKEN_AT 0
