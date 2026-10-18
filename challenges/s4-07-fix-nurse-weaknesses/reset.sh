#!/usr/bin/env bash
# s4-07 — reset: nothing to undo. Your patch is yours; git is how you unwind it.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

printf 'Nothing to undo: s4-07 is a mission and the change is a real patch.\n'
printf 'To unwind it:  cd %s && git diff && git checkout -- <the settings file>\n' "${NURSE_DIR:-/opt/nurse}"
lab_state_set 's4-07-fix-nurse-weaknesses' BROKEN_AT 0
