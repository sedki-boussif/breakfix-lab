#!/usr/bin/env bash
# s8-01 — check: the full acceptance suite, in two phases, because a rebuild
# that has never been rebooted is a rebuild nobody has tested.
#
#   check.sh --arm   run the suite now, and record the boot id
#   (then reboot)
#   check.sh         run it again, and require that the boot changed
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"
# shellcheck source=lib/accept.sh
. "$LAB_ROOT/lib/accept.sh"

ID='s8-01-build-from-nothing'
state="$(lab_state_dir "$ID")"
armed="$state/armed"
report="$LAB_ROOT/reports/${ID}.md"

if [[ "${1:-}" == "--arm" ]]; then
  printf 'Running the suite before the reboot, so you know what is still missing\n'
  printf 'before you spend a reboot on it.\n'
  accept_suite
  assert_summary || true
  printf '%s\n' "$(cat /proc/sys/kernel/random/boot_id)" >"$armed"
  printf -- '\n-- armed --------------------------------------------------------\n'
  printf 'Boot id recorded. Fix anything that failed above, then:\n'
  printf '  sudo reboot\n'
  printf '  lab check %s\n' "$ID"
  # Arming always exits 0: what it reports is a snapshot, not a verdict, and
  # the CLI knows an arming run is never a pass.
  exit 0
fi

if [[ ! -f "$armed" ]]; then
  printf 'Not armed yet. This one is proved across a reboot:\n'
  printf '  lab check %s --arm\n' "$ID"
  printf '  sudo reboot\n'
  printf '  lab check %s\n' "$ID"
  exit 1
fi

accept_rebooted "$armed"
accept_suite

# The time, which only the person who did it knows.
started="$(lab_state_get "$ID" BUILD_STARTED_AT 0)"
if [[ "$started" != 0 ]]; then
  mins=$(( ( $(date +%s) - started ) / 60 ))
  assert_pass "the build clock ran: ${mins} minutes from bare image to this check"
  printf '      put that number in the report, and in your recovery time objective\n'
else
  assert_fail "the build clock was started" \
    "lab start ${ID} starts it — without it there is no measured rebuild time to plan s8-02 against"
fi
accept_report_time "$report" "how long the rebuild took"

# Only clear the arming once it has actually passed, so a failed run can be
# fixed and re-run without spending another reboot.
if assert_summary; then
  rm -f "$armed"
  exit 0
fi
exit 1
