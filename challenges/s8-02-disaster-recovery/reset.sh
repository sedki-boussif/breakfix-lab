#!/usr/bin/env bash
# s8-02 — reset: there is nothing to undo, and saying so plainly matters more
# here than anywhere else in the catalogue. A deleted VM is not a state this
# script can leave; RISK=irreversible is the honest label and reset.sh refusing
# to pretend otherwise is part of what makes the label mean anything.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard

ID='s8-02-disaster-recovery'
state="$(lab_state_dir "$ID")"
rm -f "$state/armed"

cat <<'TXT'
Nothing undone. This challenge deletes a VM, and no script here can bring one
back — which is why its meta says RISK=irreversible and why break.sh made you
type the phrase.

What was cleared: the arming state, so the check starts from scratch.

If you are reading this on the rebuilt machine, the pre-destruction record is
gone with the old one. That is not a bug in the lab; it is the thing the
challenge was demonstrating. Whatever you need during a recovery has to live
somewhere the disaster does not reach: your Git repository, your off-site
backups, or your laptop.
TXT
lab_state_set "$ID" BROKEN_AT 0
