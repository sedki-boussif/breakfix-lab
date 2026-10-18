#!/usr/bin/env bash
# s7-03 — break: the local repository is deleted and the newest off-site
# snapshot is corrupted. Older off-site snapshots are left intact, so the
# incident is survivable with a measurable amount of loss.
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

ID='s7-03-the-backups-are-gone'
repo="${BACKUP_REPO:?}"; remote="${BACKUP_REMOTE:?}"; pw="${BACKUP_PASSWORD_FILE:?}"

# Refuse unless there is something to survive with: at least two off-site
# snapshots. A challenge that destroys the only copy is not a drill.
n="$(lab_as_root restic -r "$remote" --password-file "$pw" snapshots --json 2>/dev/null \
     | grep -o '"time"' | wc -l || echo 0)"
if (( n < 2 )); then
  printf 'refusing: the off-site repository has %s snapshot(s).\n' "$n" >&2
  printf 'This challenge removes the local copy and damages the newest remote one,\n' >&2
  printf 'so it needs at least two remote snapshots to leave you a way back.\n' >&2
  printf 'Run the backup a few times first (s7-01), then start this again.\n' >&2
  exit 1
fi

# Keep a copy of the whole off-site repository, so reset can undo the damage.
if [[ -z "$(lab_state_get "$ID" ARCHIVE '')" ]]; then
  arch="$(lab_state_dir "$ID")/offsite.tar"
  lab_as_root tar -cf "$arch" -C "$remote" . 2>/dev/null || true
  lab_as_root chown "$(id -u):$(id -g)" "$arch"
  lab_state_set "$ID" ARCHIVE "$arch"
fi
if [[ -d "$repo" && -z "$(lab_state_get "$ID" LOCAL_ARCHIVE '')" ]]; then
  larch="$(lab_state_dir "$ID")/local.tar"
  lab_as_root tar -cf "$larch" -C "$repo" . 2>/dev/null || true
  lab_as_root chown "$(id -u):$(id -g)" "$larch"
  lab_state_set "$ID" LOCAL_ARCHIVE "$larch"
fi

# Fault 1: the local repository is gone.
case "$repo" in
  /|/var|/var/backups|/srv|/etc|/home) printf 'refusing: %s is not a repository path\n' "$repo" >&2; exit 1 ;;
esac
lab_as_root rm -rf "$repo"

# Fault 2: truncate one pack file belonging to the newest snapshot, so the
# index lists it and the data cannot be read.
newest_pack="$(lab_as_root find "$remote/data" -type f -printf '%T@ %p\n' 2>/dev/null \
               | sort -rn | head -1 | cut -d' ' -f2- || true)"
if [[ -n "$newest_pack" ]]; then
  lab_as_root truncate -s 1024 "$newest_pack"
  lab_state_set "$ID" DAMAGED "$newest_pack"
fi

# And the symptom that brings someone to you: the data is gone.
( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T db \
    psql -q -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" \
    -c "TRUNCATE placements, trainees CASCADE" ) >/dev/null 2>&1 || true

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
