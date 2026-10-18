#!/usr/bin/env bash
# s4-05 — check: the score improved, SSH is actually key-only, and the open
# ports match what the lab expects in both directions.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s4-05-raise-the-hardening-score'
baseline="${LYNIS_BASELINE:-/var/lib/breakfix-lab/lynis-baseline.txt}"
report="$LAB_ROOT/reports/${ID}.md"

assert_file "a baseline score was recorded" "$baseline"
# shellcheck disable=SC2016  # the quoted body is not for this shell to expand
was="$(lab_as_root awk -F= '/^hardening_index=/{print $2}' "$baseline" 2>/dev/null | tail -1 || true)"

printf 're-running the audit (a couple of minutes)...\n'
lab_as_root lynis audit system --quick --quiet >/dev/null 2>&1 || true
# shellcheck disable=SC2016  # the quoted body is not for this shell to expand
now="$(lab_as_root awk -F= '/^hardening_index=/{print $2}' /var/log/lynis-report.dat 2>/dev/null | tail -1 || true)"

if [[ -z "$was" || -z "$now" || "$was" == unknown ]]; then
  assert_fail "the score can be compared against the baseline" \
    "baseline='${was:-}' now='${now:-}' — lab start ${ID} records the baseline"
else
  assert_above "the hardening index improved (was ${was})" "$now" "$was"
fi

# SSH, asked rather than read: a drop-in in sshd_config.d beats the main file.
eff="$(lab_as_root sshd -T 2>/dev/null || true)"
for want in 'permitrootlogin no' 'passwordauthentication no' 'pubkeyauthentication yes'; do
  if grep -qx "$want" <<<"$eff"; then
    assert_pass "sshd will actually do: ${want}"
  else
    assert_fail "sshd will actually do: ${want}" \
      "sudo sshd -T | grep ${want%% *}   # and check /etc/ssh/sshd_config.d/ for an override"
  fi
done

# The port list, in both directions.
if [[ -z "${EXPECTED_PORTS:-}" ]]; then
  assert_fail "EXPECTED_PORTS is set in lab.conf" \
    "this assertion is the point of the mission: record what should be listening"
else
  listening="$(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
  extra=""; missing=""
  for p in $listening; do
    if [[ " ${EXPECTED_PORTS} " != *" ${p} "* ]]; then extra+="${p} "; fi
  done
  for p in ${EXPECTED_PORTS}; do
    if [[ " ${listening} " != *" ${p} "* ]]; then missing+="${p} "; fi
  done
  if [[ -z "$extra" ]]; then
    assert_pass "nothing unexpected is listening"
  else
    assert_fail "nothing unexpected is listening" "extra: ${extra}"
  fi
  if [[ -z "$missing" ]]; then
    assert_pass "everything expected is still listening"
  else
    assert_fail "everything expected is still listening" \
      "missing: ${missing}— a score that went up while an application went down is the failure this mission warns about"
  fi
fi

# The judgement, which is the half worth keeping.
if [[ -f "$report" ]]; then
  assert_file_matches "the report records what was rejected, and why" \
    "$report" '[Rr]eject|[Dd]eclin|not applicable|[Dd]id not|chose not'
  assert_file_matches "the report records both scores" "$report" '[0-9]{1,3}'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the rejections are the interesting half"
fi

assert_summary
