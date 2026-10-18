#!/usr/bin/env bash
# s8-03 — check: the s8-01 suite, plus the diff that is the actual deliverable.
#
#   check.sh --arm             after the rebuild
#   (then reboot)
#   check.sh --since <sha>     the baseline break.sh printed
#
# The conditions of the challenge — no search, no documentation, no AI — are
# not checked here and could not be. What is checked is the only durable
# evidence the exercise produces: that the runbooks changed.
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

ID='s8-03-the-blind-rebuild'
armed="$(lab_state_dir "$ID")/armed"
report="$LAB_ROOT/reports/${ID}.md"
dir="${S8_RUNBOOK_DIR:-}"
arm=0
since=''

while (( $# )); do
  case "$1" in
    --arm)     arm=1 ;;
    --since)   since="${2:-}"; shift ;;
    --since=*) since="${1#*=}" ;;
    *) printf 'usage: check.sh --arm | check.sh --since <baseline sha>\n' >&2; exit 1 ;;
  esac
  shift
done

if (( arm == 1 )); then
  accept_suite
  assert_summary || true
  printf '%s\n' "$(cat /proc/sys/kernel/random/boot_id)" >"$armed"
  printf -- '\n-- armed --------------------------------------------------------\n'
  printf 'Boot id recorded. Then:\n'
  printf '  sudo reboot\n'
  printf '  lab check %s --since %s\n' "$ID" \
    "$(lab_state_get "$ID" RUNBOOK_BASELINE '<the baseline you wrote down>')"
  exit 0
fi

if [[ ! -f "$armed" ]]; then
  printf 'Not armed yet. This one is proved across a reboot:\n'
  printf '  lab check %s --arm\n  sudo reboot\n  lab check %s --since <baseline>\n' "$ID" "$ID"
  exit 1
fi

accept_rebooted "$armed"
accept_suite

# --- the deliverable: what the rebuild taught the runbooks ------------------
printf -- '-- what you had to add to your own runbooks -----------------------\n'
# The baseline from the argument, falling back to lab state — which usually
# died with the old machine, which is why the argument exists.
[[ -n "$since" ]] || since="$(lab_state_get "$ID" RUNBOOK_BASELINE '')"

if [[ -z "$dir" ]]; then
  assert_fail "S8_RUNBOOK_DIR is set in lab.conf" \
    "the diff against your runbooks is what this challenge produces"
elif [[ ! -d "$dir" ]] || ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  assert_fail "the runbooks are a Git repository at ${dir}" \
    "without history there is no before and after to compare"
elif [[ -z "$since" ]]; then
  assert_fail "the baseline commit was given" \
    "lab check ${ID} --since <sha>   # the seven characters break.sh printed"
elif ! git -C "$dir" rev-parse --verify --quiet "${since}^{commit}" >/dev/null; then
  assert_fail "the baseline commit ${since} exists in ${dir}" \
    "git -C ${dir} log --oneline | tail   # and check you pushed the baseline before rebuilding"
else
  commits="$(git -C "$dir" rev-list --count "${since}..HEAD" 2>/dev/null || echo 0)"
  assert_above "the runbooks have commits since ${since}" "$commits" 0 " commit(s)"

  added="$(git -C "$dir" diff --numstat "${since}..HEAD" 2>/dev/null \
           | awk '{a+=$1} END{print a+0}')"
  assert_above "and those commits added lines" "$added" 0 " line(s)"

  # Uncommitted work is the most common way the diff comes out empty: the gap
  # was written down and never committed, so nothing survives the next machine.
  dirty="$(git -C "$dir" status --porcelain 2>/dev/null || true)"
  if [[ -z "$dirty" ]]; then
    assert_pass "nothing is left uncommitted in the runbooks"
  else
    assert_fail "nothing is left uncommitted in the runbooks" \
      "a gap written down but not committed does not survive the next rebuild — git -C ${dir} status"
  fi

  if (( commits > 0 )); then
    printf '\n      the deliverable:\n'
    git -C "$dir" diff --stat "${since}..HEAD" 2>/dev/null | sed 's/^/      /'
    printf '\n'
    git -C "$dir" log --oneline "${since}..HEAD" 2>/dev/null | sed 's/^/      /'
    printf '\n'
  fi
fi

accept_report_time "$report" "how long the blind rebuild took"
if [[ -f "$report" ]]; then
  assert_file_matches "the report lists what you had to work out" \
    "$report" '[Gg]ap|[Ss]tuck|[Ff]rom memory|had to work out|[Mm]issing from the runbook|[Nn]othing was missing'
  assert_file_matches "the report attests to the conditions it was done under" \
    "$report" '[Nn]o search|[Nn]o internet|[Nn]o AI|[Bb]lind|only my own|runbooks only'
fi

if assert_summary; then
  rm -f "$armed"
  exit 0
fi
exit 1
