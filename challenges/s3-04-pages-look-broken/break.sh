#!/usr/bin/env bash
# s3-04 — break: empty STATIC_ROOT and remove the WhiteNoise manifest. HTML
# still renders; every asset 404s.
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
static_root="${LEAVES_STATIC_ROOT:?set LEAVES_STATIC_ROOT in lab.conf}"
[[ -d "$static_root" ]] || { printf 'no static root at %s\n' "$static_root" >&2; exit 1; }

# Refuse to run against a path that is not a collectstatic target: this deletes
# files, so it checks what it is pointed at first.
case "$static_root" in
  /|/etc|/home|/usr|/var|/opt) printf 'refusing: %s is not a static root\n' "$static_root" >&2; exit 1 ;;
esac

if [[ -z "$(lab_state_get "$ID" ARCHIVE '')" ]]; then
  archive="$(lab_state_dir "$ID")/static-root.tar"
  lab_as_root tar -cf "$archive" -C "$static_root" . 2>/dev/null || true
  lab_as_root chown "$(id -u):$(id -g)" "$archive"
  lab_state_set "$ID" ARCHIVE "$archive"
fi

lab_as_root find "$static_root" -mindepth 1 -delete 2>/dev/null || true
svc_restart leaves web >/dev/null 2>&1 || true

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
