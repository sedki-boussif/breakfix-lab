#!/usr/bin/env bash
# s8-02 — check: the s8-01 suite, plus the three things a recovery has to prove
# that a build does not — that the data came back, all of it, and in time.
#
#   check.sh --arm                 after the rebuild
#   (then reboot)
#   check.sh --minutes <elapsed>   the measured recovery time
#
# Nothing here reads anything written before the deletion, because the deletion
# destroyed it. Everything this check needs comes from the archive, from
# lab.conf in Git, or from the person who did the work — which is the same
# constraint the recovery itself was under.
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

ID='s8-02-disaster-recovery'
armed="$(lab_state_dir "$ID")/armed"
report="$LAB_ROOT/reports/${ID}.md"
arm=0
minutes=''

while (( $# )); do
  case "$1" in
    --arm)      arm=1 ;;
    --minutes)  minutes="${2:-}"; shift ;;
    --minutes=*) minutes="${1#*=}" ;;
    *) printf 'usage: check.sh --arm | check.sh --minutes <elapsed>\n' >&2; exit 1 ;;
  esac
  shift
done

if (( arm == 1 )); then
  printf 'Running the suite before the reboot, so you know what the recovery\n'
  printf 'still owes you before you spend a reboot on it.\n'
  accept_suite
  assert_summary || true
  printf '%s\n' "$(cat /proc/sys/kernel/random/boot_id)" >"$armed"
  printf -- '\n-- armed --------------------------------------------------------\n'
  printf 'Boot id recorded. Then:\n'
  printf '  sudo reboot\n'
  printf '  lab check %s --minutes <your elapsed minutes>\n' "$ID"
  exit 0
fi

if [[ ! -f "$armed" ]]; then
  printf 'Not armed yet. This one is proved across a reboot:\n'
  printf '  lab check %s --arm\n  sudo reboot\n  lab check %s --minutes <elapsed>\n' "$ID" "$ID"
  exit 1
fi

accept_rebooted "$armed"
accept_suite

# --- the data came back, all of it ------------------------------------------
printf -- '-- the data the archive held is the data being served -------------\n'
fp="${BACKUP_FINGERPRINT:-}"
restored="${S8_RESTORE_TARGET:-/var/tmp/s8-restore}${fp}"
if [[ -z "$fp" ]]; then
  assert_fail "BACKUP_FINGERPRINT is set in lab.conf" \
    "without it there is nothing to compare a restore against"
else
  # accept_backup_restored, run moments ago by accept_suite, restored the
  # fingerprint from the latest snapshot to this path. Comparing every line of
  # it rather than one is the assertion s8-01 does not make.
  accept_fingerprint_matches_live "$restored"
fi

# --- and it came back in time ----------------------------------------------
printf -- '\n-- against the objective you wrote down before you knew ----------\n'
target="${S8_RTO_MINUTES:-}"
if [[ -z "$minutes" ]]; then
  assert_fail "the elapsed recovery time was given" \
    "lab check ${ID} --minutes <elapsed>   # the number this drill exists to produce"
elif [[ ! "$minutes" =~ ^[0-9]+$ ]]; then
  assert_fail "the elapsed recovery time is a number of minutes" "got '${minutes}'"
elif [[ -z "$target" ]]; then
  assert_fail "S8_RTO_MINUTES is set in lab.conf" \
    "you recovered in ${minutes} minutes, but there is nothing to compare it against. The objective is the number you commit to BEFORE the drill — s7-02 is where it was written down"
else
  assert_pass "the recovery took ${minutes} minutes"
  assert_below "it came in under the objective of ${target} minutes" "$minutes" "$target" " min"
  if (( minutes * 2 < target )); then
    printf '      %s minutes against an objective of %s: either the drill was easier\n' "$minutes" "$target"
    printf '      than the disaster will be, or the objective has room to come down.\n'
  fi
fi

# --- and the gaps are written down -----------------------------------------
if [[ -f "$report" ]]; then
  assert_file_matches "the report names what had to be improvised" \
    "$report" '[Ii]mprovis|[Gg]ap|[Mm]issing|[Nn]ot in the runbook|had to work out|[Ff]rom memory|[Gg]uess'
  assert_file_matches "the report records the loss window, or states there was none" \
    "$report" '[Ll]oss window|[Dd]ata loss|[Nn]othing was lost|RPO|[Ll]ast (archive|snapshot|backup)'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the elapsed time, the loss window, and every step you had to improvise"
fi

if assert_summary; then
  rm -f "$armed"
  exit 0
fi
exit 1
