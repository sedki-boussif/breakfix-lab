#!/usr/bin/env bash
# s8-02 — a mission, and the only one whose "break" is performed by the person
# rather than the script: deleting a VM from inside it is not something this
# lab will do, and a script that could would be a worse thing to own than any
# challenge in the catalogue.
#
# What this does is take the record you will want afterwards, check that the
# backups are actually survivable, and make you type the phrase.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s8-02-disaster-recovery'
record="$(lab_state_dir "$ID")/pre-destruction-record.txt"

printf 'Nothing is broken yet. You are going to delete this VM yourself.\n\n'

# --- is there anything to rebuild from? -------------------------------------
printf 'Before anything else: can the backups survive this machine?\n'
ok=1
repo="${BACKUP_REMOTE:-}"; pw="${BACKUP_PASSWORD_FILE:-}"
if [[ -z "$repo" || -z "$pw" ]]; then
  printf '  NO   BACKUP_REMOTE or BACKUP_PASSWORD_FILE is not set in lab.conf\n'
  ok=0
else
  if lab_as_root restic -r "$repo" --password-file "$pw" snapshots >/dev/null 2>&1; then
    n="$(lab_as_root restic -r "$repo" --password-file "$pw" snapshots --json 2>/dev/null \
         | grep -o '"time"' | wc -l || true)"
    printf '  yes  %s lists %s snapshot(s)\n' "$repo" "${n:-0}"
    [[ "${n:-0}" != 0 ]] || ok=0
  else
    printf '  NO   %s does not answer: no snapshots to rebuild from\n' "$repo"
    ok=0
  fi
  remote_fs="$(findmnt -n -o TARGET --target "$repo" 2>/dev/null || true)"
  local_fs="$(findmnt -n -o TARGET --target / 2>/dev/null || true)"
  if [[ -n "$remote_fs" && "$remote_fs" != "$local_fs" ]]; then
    printf '  yes  it is on its own filesystem (%s)\n' "$remote_fs"
  else
    printf '  NO   it is on the root filesystem, which dies with the disk\n'
    ok=0
  fi
fi

# A reminder rather than a gate: whether the backup filesystem is really off
# this VM is a judgement about your hypervisor, and only you can make it.
printf '\n  And one this script cannot check for you: "its own filesystem" is\n'
printf '  still a file on this hypervisor unless you made it something else.\n'
printf '  If deleting this VM takes %s with it, stop now.\n' "${BACKUP_REMOTE_MNT:-the backup mount}"

if (( ok == 0 )); then
  printf '\nRefusing to start: deleting this VM now would be data loss with a\n' >&2
  printf 'lesson attached rather than a drill. Fix the backups first (s7-01).\n' >&2
  exit 1
fi

# --- the record, which the deletion will destroy ----------------------------
{
  printf '# s8-02 pre-destruction record, %s\n' "$(date '+%F %T %Z')"
  printf '# Save this OFF the VM. It is the first thing people lose.\n\n'
  printf 'listening_ports=%s\n' \
    "$(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
  printf 'accounts=%s\n' \
    "$(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd | sort | tr '\n' ' ')"
  printf 'rto_minutes=%s\n' "${S8_RTO_MINUTES:-<unset in lab.conf>}"
  printf '\n# row counts, as the archive should also record them\n'
  if [[ -n "${BACKUP_FINGERPRINT:-}" ]] && lab_as_root test -s "$BACKUP_FINGERPRINT"; then
    lab_as_root cat "$BACKUP_FINGERPRINT"
  else
    printf '# no fingerprint at %s — the restore will have nothing to be checked against\n' \
      "${BACKUP_FINGERPRINT:-<unset>}"
  fi
} >"$record"

printf '\nRecord written to:\n  %s\n' "$record"
printf 'It is on the VM you are about to delete. Copy it off, now:\n'
printf '  scp %s you@your-laptop:\n\n' "$record"
sed 's/^/  | /' "$record"

lab_require_confirm 'delete-the-vm' \
"$(printf 'This is the only challenge where the lab does not undo anything.\nreset.sh cannot bring back a deleted VM, and there is no snapshot step\nthat helps: the snapshot is the thing you are choosing not to use.')"

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
printf '\nConfirmed. Note the wall-clock time now — that is minute zero.\n'
printf 'Then delete the VM from the hypervisor, disk and all, and rebuild from\n'
printf 'your Git repository and %s alone.\n' "${BACKUP_REMOTE:-your off-site repository}"
printf '\nWhen it is back:\n'
printf '  lab check %s --arm\n' "$ID"
printf '  sudo reboot\n'
printf '  lab check %s --minutes <elapsed>\n' "$ID"
