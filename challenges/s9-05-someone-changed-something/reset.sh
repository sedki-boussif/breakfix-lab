#!/usr/bin/env bash
# s9-05 — reset: put the timezone back and refresh the report.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s9-05-someone-changed-something'
was="$(lab_state_get "$ID" WAS_TZ 'UTC')"
lab_as_root timedatectl set-timezone "$was" >/dev/null 2>&1 || true
job="${LAB_JOB_DIR:-/opt/lab-jobs}/nightly-report.sh"
if [[ -x "$job" ]]; then
  lab_as_root env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$job" || true
fi
lab_state_set "$ID" BROKEN_AT 0
