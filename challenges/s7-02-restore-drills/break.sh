#!/usr/bin/env bash
# s7-02 — a mission: nothing is broken. This records the live row counts so the
# check can prove afterwards that the drills did not touch them.
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

ID='s7-02-restore-drills'
live="$(lab_state_dir "$ID")/live-counts-before"

( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
    psql -tAq -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" \
    -c "SELECT 'trainees='||count(*) FROM trainees
        UNION ALL SELECT 'placements='||count(*) FROM placements
        UNION ALL SELECT 'audit_log='||count(*) FROM audit_log" ) >"$live" 2>/dev/null || true

printf 'Nothing is broken: this is a mission.\n'
printf 'Live row counts recorded, so the check can prove your drills did not touch them:\n'
sed 's/^/  /' "$live" 2>/dev/null || printf '  (could not read them — is stages up?)\n'
printf '\nRun the three drills, record the times, then: lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
