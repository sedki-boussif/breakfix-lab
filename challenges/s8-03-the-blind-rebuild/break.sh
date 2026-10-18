#!/usr/bin/env bash
# s8-03 — a mission: nothing is broken. What this does is record the one thing
# that has to survive the rebuild — where the runbooks were before it started —
# and say the conditions out loud, because they are not enforceable and a
# condition nobody restated is a condition nobody kept.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s8-03-the-blind-rebuild'
dir="${S8_RUNBOOK_DIR:-}"

printf 'Nothing is broken: this is a mission, and the subject of it is your\n'
printf 'documentation rather than this machine.\n\n'

if [[ -z "$dir" ]]; then
  printf 'S8_RUNBOOK_DIR is not set in lab.conf.\n' >&2
  printf 'This challenge is scored on what you add to your runbooks, so it needs\n' >&2
  printf 'to know where they are — a Git repository of their own, not this one.\n' >&2
  exit 1
fi
if [[ ! -d "$dir" ]]; then
  printf 'S8_RUNBOOK_DIR points at %s, which does not exist.\n' "$dir" >&2
  exit 1
fi
if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  printf '%s is not a Git repository.\n' "$dir" >&2
  printf 'The check compares your runbooks before and after, which needs history.\n' >&2
  printf '  git -C %s init && git -C %s add -A && git -C %s commit -m "runbooks before the blind rebuild"\n' \
    "$dir" "$dir" "$dir"
  exit 1
fi

dirty="$(git -C "$dir" status --porcelain 2>/dev/null || true)"
if [[ -n "$dirty" ]]; then
  printf 'Your runbooks have uncommitted changes:\n'
  git -C "$dir" status --porcelain 2>/dev/null | sed 's/^/  /'
  printf '\nCommit them first. The baseline has to be a commit, or "what I added\n'
  printf 'during the rebuild" and "what I had not got round to committing" become\n'
  printf 'the same diff, and the exercise measures nothing.\n' >&2
  exit 1
fi

baseline="$(git -C "$dir" rev-parse --short HEAD)"
lab_state_set "$ID" RUNBOOK_BASELINE "$baseline"
lab_state_set "$ID" BUILD_STARTED_AT "$(date +%s)"

printf 'Runbooks: %s\n' "$dir"
printf '  %s files, %s commits, baseline:\n\n' \
  "$(git -C "$dir" ls-files | wc -l)" "$(git -C "$dir" rev-list --count HEAD)"
printf '      %s\n\n' "$baseline"
printf 'Write that down. On paper, or on your laptop — not on this VM, which you\n'
printf 'are about to replace. The check needs it, and it is seven characters.\n'

cat <<'TXT'

The conditions, restated because nothing enforces them:

  allowed      your own runbooks; the package mirrors; this machine's own
               output — systemctl, journalctl, ss, sshd -T, nginx -t; and
               lab.conf, which is configuration rather than instruction
  not allowed  search, documentation sites, manual pages you did not write,
               AI, and SETUP.md

When you get stuck: fix the runbook, commit it, then carry on. In that order.
Writing it up afterwards from memory is how the same gap survives three
rebuilds — what you remember is that you were stuck, not what you needed.
TXT

printf '\nThen: a bare Ubuntu 24.04 image, rebuild, and\n'
printf '  lab check %s --arm\n' "$ID"
printf '  sudo reboot\n'
printf '  lab check %s --since %s\n' "$ID" "$baseline"
lab_state_set "$ID" BROKEN_AT 0
