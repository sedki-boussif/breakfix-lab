#!/usr/bin/env bash
# s3-04 — reset: put the collected static files back from the archive taken
# before the break, and restart so WhiteNoise rescans.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-04-pages-look-broken'
static_root="${LEAVES_STATIC_ROOT:?}"
archive="$(lab_state_get "$ID" ARCHIVE '')"

if [[ -n "$archive" && -f "$archive" ]]; then
  lab_as_root mkdir -p "$static_root"
  lab_as_root tar -xf "$archive" -C "$static_root"
fi
svc_restart leaves web >/dev/null 2>&1 || true
lab_state_set "$ID" BROKEN_AT 0
