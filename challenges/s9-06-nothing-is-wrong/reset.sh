#!/usr/bin/env bash
# s9-06 — reset: nothing to undo, because nothing was done.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
lab_state_set 's9-06-nothing-is-wrong' BROKEN_AT 0
