#!/usr/bin/env bash
# s6-06 — reset: put the checkout back where break.sh found it, and clear the
# deploy record. The script the user wrote is their work and is left alone.
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
start_ref="$(lab_state_get "$ID" START_REF '')"
start_desc="$(lab_state_get "$ID" START_DESC '')"

if [[ -n "$start_ref" ]] && [[ -d "$dir/.git" ]]; then
  if git -C "$dir" checkout -q --detach "$start_ref" 2>/dev/null; then
    printf 'Checkout returned to %s (%s).\n' "${start_desc:-$start_ref}" "${start_ref:0:8}"
  else
    printf 'Could not return the checkout to %s — do it by hand:\n' "$start_ref" >&2
    printf '  git -C %s checkout --detach %s\n' "$dir" "$start_ref" >&2
  fi
else
  printf 'No recorded starting commit, so the checkout was left where it is.\n'
  printf 'Where that is: %s\n' \
    "$(git -C "$dir" describe --tags --always 2>/dev/null || echo unknown)"
fi

if lab_as_root test -e "$state"; then
  lab_as_root rm -f "$state"
  printf 'Removed the deploy record %s.\n' "$state"
fi

printf '\nThe tags you made were left alone — they are the artefact of the\n'
printf 'exercise. To remove them: git -C %s tag -d <name>\n' "$dir"
if [[ -e "$script" ]]; then
  printf '%s was left alone too; it is your work.\n' "$script"
fi
printf '\nRestart the app if a half-finished deploy left it down:\n'
printf '  %s <a tag>   # or lab doctor, which will say what is not answering\n' "$script"
lab_state_set "$ID" BROKEN_AT 0
