#!/usr/bin/env bash
# s6-06 — a mission: nothing is broken. This shows what the checkout is at now
# and records it, so the check can put the machine back where it found it.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-06-deploy-by-tag'
app="${S6_06_APP:-leaves}"
dirvar="$(printf '%s_DIR' "${app^^}")"
dir="${!dirvar:-/opt/$app}"
script="${S6_06_DEPLOY_SCRIPT:-/usr/local/bin/deploy.sh}"
state="${S6_06_DEPLOY_STATE:-/var/lib/breakfix-lab/deployed-tags}"

printf 'Nothing is broken: this is a mission.\n\n'

if [[ ! -d "$dir/.git" ]]; then
  printf '%s is not a git checkout.\n' "$dir" >&2
  printf 'This mission is about deploying a named version of it, which needs\n' >&2
  printf 'history. SETUP.md section 6 clones it; if you copied the files\n' >&2
  printf 'instead, re-clone before starting.\n' >&2
  exit 1
fi

printf 'The checkout: %s\n' "$dir"
printf '  HEAD:     %s\n' "$(git -C "$dir" rev-parse --short HEAD)"
printf '  describes as: %s\n' "$(git -C "$dir" describe --tags --always --dirty 2>/dev/null || echo 'no tags yet')"
printf '  branch:   %s\n' "$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
printf '  tags:     %s\n' "$(git -C "$dir" tag | tr '\n' ' ' | sed 's/ $//' || true)"
dirty="$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)"
printf '  uncommitted changes: %s\n' "$dirty"

# Record where we started, so the check can restore it.
lab_state_set "$ID" START_REF "$(git -C "$dir" rev-parse HEAD)"
lab_state_set "$ID" START_DESC "$(git -C "$dir" describe --tags --always 2>/dev/null || echo unknown)"

printf '\nWrite the deploy script here:\n  %s\n' "$script"
if [[ -e "$script" ]]; then
  printf '  (something is already there, %s bytes — not touched)\n' "$(stat -c '%s' "$script")"
fi
printf 'And have it record what it deployed here:\n  %s\n' "$state"

printf '\nYou need at least two tags with a VISIBLE difference between them —\n'
printf 'the rollback has to be observable or it cannot be verified. Something\n'
printf 'the running app will show you: a template string, a version constant,\n'
printf 'a heading.\n'

printf '\nThe check will run your script twice against the real application and\n'
printf 'require the response to change and change back. It puts you back on\n'
printf '%s when it is done, whichever way the assertions went.\n' \
  "$(git -C "$dir" describe --tags --always 2>/dev/null || echo 'where you are now')"

printf '\nWhen it works:\n  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
