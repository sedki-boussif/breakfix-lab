#!/usr/bin/env bash
# s4-05 — a mission: nothing is broken. This records the baseline score, which
# is the thing the improvement is measured against.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-05-raise-the-hardening-score'
baseline="${LYNIS_BASELINE:-/var/lib/breakfix-lab/lynis-baseline.txt}"

command -v lynis >/dev/null 2>&1 || {
  printf 'lynis is not installed: sudo apt install -y lynis\n' >&2; exit 1; }

if [[ ! -s "$baseline" ]]; then
  printf 'Running the baseline audit. This takes a couple of minutes.\n'
  lab_as_root mkdir -p "$(dirname "$baseline")"
  lab_as_root lynis audit system --quick --quiet >/dev/null 2>&1 || true
  # shellcheck disable=SC2016  # the quoted body is not for this shell to expand
  score="$(lab_as_root awk -F= '/^hardening_index=/{print $2}' /var/log/lynis-report.dat 2>/dev/null | tail -1)"
  {
    printf 'taken=%s\n' "$(date -Is)"
    printf 'hardening_index=%s\n' "${score:-unknown}"
  } | lab_as_root tee "$baseline" >/dev/null
  printf 'Baseline hardening index: %s  (recorded in %s)\n' "${score:-unknown}" "$baseline"
else
  printf 'Baseline already recorded in %s:\n' "$baseline"
  lab_as_root sed 's/^/  /' "$baseline"
fi

printf '\nFix the top five findings you agree with, then: lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
