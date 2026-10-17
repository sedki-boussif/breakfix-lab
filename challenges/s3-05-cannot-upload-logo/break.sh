#!/usr/bin/env bash
# s3-05 — break: the uploads volume on the host stops being writable by the uid
# the api runs as. The endpoint then returns 500 with the errno.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-05-cannot-upload-logo'
vol="${STAGES_UPLOADS_VOLUME:?set STAGES_UPLOADS_VOLUME in lab.conf}"

path="$(lab_as_root docker volume inspect -f '{{.Mountpoint}}' "$vol" 2>/dev/null || true)"
[[ -n "$path" && -d "$path" ]] || { printf 'cannot find the mountpoint of volume %s\n' "$vol" >&2; exit 1; }

# Record what it was, once, so reset restores the real owner rather than a guess.
if [[ -z "$(lab_state_get "$ID" OWNER '')" ]]; then
  lab_state_set "$ID" OWNER "$(stat -c '%u:%g' "$path")"
  lab_state_set "$ID" MODE  "$(stat -c '%a' "$path")"
  lab_state_set "$ID" PATH_ "$path"
fi

lab_as_root chown 0:0 "$path"
lab_as_root chmod 755 "$path"

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
