#!/usr/bin/env bash
# s5-09 — check: the report is fresh, and the job works in cron's environment
# rather than in yours. Running it by hand refreshes the file and fixes nothing.
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

out="${LAB_JOB_OUT:-/var/lib/lab-jobs/report.csv}"
job="${LAB_JOB_DIR:-/opt/lab-jobs}/nightly-report.sh"
max_age_h="${LAB_JOB_MAX_AGE_H:-30}"
cron_file='/etc/cron.d/lab-nightly-report'

assert_file "the report exists" "$out"

# A measurement: how old is it.
if [[ -f "$out" ]]; then
  age_h=$(( ( $(date +%s) - $(stat -c '%Y' "$out") ) / 3600 ))
  assert_below "the report is fresh" "$age_h" "$max_age_h" "h"
else
  assert_fail "the report is fresh" "there is no report to age"
fi

# The end state that matters: the job works in the environment its SCHEDULE
# gives it, which is not the environment of whoever is logged in.
#
# Not a bare `env -i`: that leaves sh to pick a default PATH, which on Debian
# and Ubuntu includes /usr/local/bin — so a bare env -i passes the broken job
# and asserts nothing. The faithful test is the PATH the crontab itself sets,
# defaulting to cron's own /usr/bin:/bin when it sets none.
#
# This accepts either legitimate fix: an explicit PATH in the schedule, or
# absolute paths inside the script.
cron_path='/usr/bin:/bin'
if [[ -f "$cron_file" ]]; then
  from_cron="$(grep -m1 '^PATH=' "$cron_file" 2>/dev/null | cut -d= -f2- || true)"
  [[ -z "$from_cron" ]] || cron_path="$from_cron"
fi
assert_cmd "the job succeeds with the PATH its schedule provides (${cron_path})" \
  lab_as_root env -i PATH="$cron_path" /bin/sh -c "$(printf '%q' "$job")"

# Note on what is NOT asserted here. "Nothing depends on an interactive PATH"
# is the same claim as "the job succeeds under env -i", which is asserted above
# and is positive: running the real job in cron's own environment is itself the
# evidence, so there is nothing for a planted control to add. An absence
# assertion pointed at a control script would prove only that the detector
# works, while saying nothing about the job.

assert_summary
