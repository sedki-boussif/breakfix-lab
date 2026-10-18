#!/usr/bin/env bash
# s4-05 — reset: forget the baseline so the mission can be redone from scratch.
# Your hardening changes are yours and are not touched.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

lab_as_root rm -f "${LYNIS_BASELINE:-/var/lib/breakfix-lab/lynis-baseline.txt}"
printf 'Baseline forgotten. Your hardening changes are untouched — they are yours.\n'
lab_state_set 's4-05-raise-the-hardening-score' BROKEN_AT 0
