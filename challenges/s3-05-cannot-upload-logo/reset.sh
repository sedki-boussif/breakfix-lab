#!/usr/bin/env bash
# s3-05 — reset: give the volume back to its original owner and mode.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s3-05-cannot-upload-logo'
path="$(lab_state_get "$ID" PATH_ '')"
owner="$(lab_state_get "$ID" OWNER '')"
mode="$(lab_state_get "$ID" MODE '')"

if [[ -n "$path" && -d "$path" && -n "$owner" ]]; then
  lab_as_root chown "$owner" "$path"
  lab_as_root chmod "${mode:-775}" "$path"
fi
lab_state_set "$ID" BROKEN_AT 0
