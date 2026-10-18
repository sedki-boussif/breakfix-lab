#!/usr/bin/env bash
# s7-04 — a mission: nothing is broken. This records which archive the check
# will try to delete, so the proof is against a specific file rather than a
# hopeful one.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-04-append-only-backups'
remote="${BACKUP_REMOTE:?}"

victim="$(lab_as_root find "$remote/data" -type f -printf '%T@ %p\n' 2>/dev/null \
          | sort -n | head -1 | cut -d' ' -f2- || true)"
if [[ -z "$victim" ]]; then
  printf 'The off-site repository has no data files yet.\n' >&2
  printf 'Finish s7-01 and run the backup at least once, then start this again.\n' >&2
  exit 1
fi
lab_state_set "$ID" VICTIM "$victim"
lab_as_root sha256sum "$victim" | cut -d' ' -f1 > "$(lab_state_dir "$ID")/victim.sha256"

printf 'Nothing is broken: this is a mission.\n'
printf 'The check will try to delete this file, as root, and require the attempt to fail:\n'
printf '  %s\n' "$victim"
printf '\nMake the off-site copy append-only, then: lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
