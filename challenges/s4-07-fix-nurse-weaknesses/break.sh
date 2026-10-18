#!/usr/bin/env bash
# s4-07 — a mission: nothing is broken. This records which settings module the
# deployment actually loads, so the work starts from fact rather than from a
# guess about a repository with duplicate files at its root.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-07-fix-nurse-weaknesses'
dir="${NURSE_DIR:?}"
env_file="${NURSE_ENV:?}"

mod="$(lab_as_root sed -n 's/^DJANGO_SETTINGS_MODULE=//p' "$env_file" 2>/dev/null | tail -1)"
printf 'Nothing is broken: this is a mission.\n\n'
printf 'The deployment loads: DJANGO_SETTINGS_MODULE=%s\n' "${mod:-<unset>}"
if [[ -n "$mod" ]]; then
  path="${dir}/${mod//.//}.py"
  printf 'which is: %s\n' "$path"
  if [[ -f "$path" ]]; then
    printf '\nThe two lines to look at:\n'
    grep -nE 'SECRET_KEY|DEBUG' "$path" 2>/dev/null | sed 's/^/  /' || true
  else
    printf '\nThat file is not where I expected. Find it before editing anything:\n'
    printf '  ls %s\n' "$dir"
  fi
fi
printf '\nRemember this repository has duplicate files at its root: edit the canonical\n'
printf 'copy, not a copy nothing imports.\n'
printf '\nThen: lab check %s\n' "$ID"
lab_state_set "$ID" MODULE "${mod:-}"
lab_state_set "$ID" BROKEN_AT 0
