#!/usr/bin/env bash
# s6-01 — reset: nothing to undo automatically. Unwinding a storage move is a
# deliberate act, and doing it for you would be more dangerous than useful.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard

ID='s6-01-give-docker-its-own-volume'
rm -f "$(lab_state_dir "$ID")/armed" "$(lab_state_dir "$ID")/lv-size"

cat <<'TXT'
Nothing undone: s6-01 is a mission, and unwinding a storage move automatically
would be more dangerous than useful. To do it yourself, in this order:

  sudo systemctl stop docker docker.socket
  sudo umount /var/lib/docker
  # remove the fstab line you added
  sudo mount -a                      # must be silent
  # restore the old copy if you kept it, or let Docker rebuild from empty
  sudo systemctl start docker
  # then, only when you are sure:
  sudo lvremove /dev/dockervg/dockerlv && sudo vgremove dockervg && sudo pvremove /dev/sdX

The arming state has been cleared, so the check starts from scratch.
TXT
lab_state_set "$ID" BROKEN_AT 0
