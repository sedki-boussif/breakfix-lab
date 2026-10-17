#!/usr/bin/env bash
# s5-09 — break: the nightly job depends on a PATH only an interactive shell
# has, so it fails under cron and produces nothing. The stale output stays.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s5-09-nightly-job-stopped'
job_dir="${LAB_JOB_DIR:-/opt/lab-jobs}"
out="${LAB_JOB_OUT:-/var/lib/lab-jobs/report.csv}"
job="$job_dir/nightly-report.sh"
helper='/usr/local/bin/labreport'
cron_file='/etc/cron.d/lab-nightly-report'

lab_as_root mkdir -p "$job_dir" "$(dirname "$out")"

# The helper that only an interactive PATH finds. Harmless and real.
if [[ ! -x "$helper" ]]; then
  # shellcheck disable=SC2016  # the $(( )) belongs to the generated script
  printf '#!/bin/sh\n# Formats the nightly placement report. Invented data only.\nprintf "ward,placements\\nWard Alpha,%%s\\nWard Bravo,%%s\\n" "$((RANDOM %% 40))" "$((RANDOM %% 40))"\n' |
    lab_as_root tee "$helper" >/dev/null
  lab_as_root chmod 0755 "$helper"
  lab_state_set "$ID" CREATED_HELPER 1
fi

# The job itself: calls the helper by name, not by path. Correct-looking, and
# only correct in a shell that has /usr/local/bin.
if [[ ! -f "$job" ]]; then
  printf '#!/bin/sh\nset -e\nlabreport > "%s"\n' "$out" | lab_as_root tee "$job" >/dev/null
  lab_as_root chmod 0755 "$job"
  lab_state_set "$ID" CREATED_JOB 1
fi

# A schedule with cron's own minimal PATH, which is the fault.
if [[ ! -f "$cron_file" ]]; then
  printf 'PATH=/usr/bin:/bin\n17 2 * * * root %s\n' "$job" |
    lab_as_root tee "$cron_file" >/dev/null
  lab_as_root chmod 0644 "$cron_file"
  lab_state_set "$ID" CREATED_CRON 1
fi

# Three weeks of stale output, so the symptom is an age rather than an absence.
lab_as_root sh -c "printf 'ward,placements\nWard Alpha,18\nWard Bravo,11\n' > '$out'"
lab_as_root touch -d '23 days ago' "$out"

lab_state_set "$ID" JOB "$job"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
