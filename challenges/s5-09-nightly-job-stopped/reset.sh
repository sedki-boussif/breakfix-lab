#!/usr/bin/env bash
# s5-09 — reset: remove what the break created, and leave a fresh report.
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
cron_file='/etc/cron.d/lab-nightly-report'

# A correct schedule: an explicit PATH that includes where the helper lives.
if [[ "$(lab_state_get "$ID" CREATED_CRON 0)" == 1 ]]; then
  printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n17 2 * * * root %s\n' "$job" |
    lab_as_root tee "$cron_file" >/dev/null
  lab_as_root chmod 0644 "$cron_file"
fi
if [[ -x "$job" ]]; then
  lab_as_root mkdir -p "$(dirname "$out")"
  lab_as_root env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$job" || true
fi
lab_state_set "$ID" BROKEN_AT 0
