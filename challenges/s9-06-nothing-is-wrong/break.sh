#!/usr/bin/env bash
# s9-06 — break: nothing. This is a genuine no-op, and that is the challenge.
#
# It records that the round started, and changes nothing else on the machine.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s9-06-nothing-is-wrong'
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
