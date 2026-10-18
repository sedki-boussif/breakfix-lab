#!/usr/bin/env bash
# s6-01 — a mission: nothing is broken. This checks the preconditions, because
# the most expensive mistake here is starting without the second disk and
# improvising onto one that matters.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-01-give-docker-its-own-volume'

printf 'Nothing is broken: this is a mission.\n\n'
printf 'Block devices on this machine:\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | sed 's/^/  /'

# A blank disk: a whole disk, no filesystem, no mountpoint, no children.
blank="$(lsblk -dnro NAME,TYPE,FSTYPE,MOUNTPOINT | awk '$2=="disk" && $3=="" && $4=="" {print $1}' | head -1)"
printf '\n'
if [[ -z "$blank" ]]; then
  printf 'No blank unpartitioned disk found.\n'
  printf 'This mission needs the second disk from SETUP.md section 2, attached and\n'
  printf 'untouched. A loopback file is documented there as a fallback and is NOT\n'
  printf 'equivalent: it is backed by the filesystem you would be moving off, so\n'
  printf 'nothing is really separated and the reboot test proves much less.\n'
  printf '\nAttach the disk, then start this again.\n'
else
  printf 'Candidate blank disk: /dev/%s\n' "$blank"
  printf 'Confirm that is the one you attached for this before you write to it.\n'
  lab_state_set "$ID" CANDIDATE "/dev/${blank}"
fi

printf '\nCurrent state of what you are moving:\n'
printf '  %s\n' "$(df -h /var/lib/docker | tail -1)"
printf '  %s\n' "$(du -xsh /var/lib/docker 2>/dev/null || echo 'cannot size /var/lib/docker')"

printf '\nBuild the stack and move the data, then arm the check:\n'
printf '  lab check %s --arm\n' "$ID"
printf 'then extend the volume, reboot, and:\n'
printf '  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
