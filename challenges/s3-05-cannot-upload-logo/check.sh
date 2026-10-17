#!/usr/bin/env bash
# s3-05 — check: an upload is written and read back, the path is traversable,
# and neither shortcut was taken — not world-writable, and not running as root.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

base="${STAGES_URL:?}"
vol="${STAGES_UPLOADS_VOLUME:?}"
name="lab-logo-$$.png"
tmp="$(mktemp)"; printf 'not-a-real-png-%s\n' "$$" >"$tmp"
trap 'rm -f "$tmp"' EXIT

# The end state the user cares about: a file goes in and comes back out.
assert_cmd "an upload is accepted" \
  curl -fsS -o /dev/null --max-time 20 -F "file=@${tmp};filename=${name}" \
  "${base%/}/api/uploads/"
assert_http "the uploaded file reads back" "${base%/}/api/uploads/${name}/" 200

path="$(lab_as_root docker volume inspect -f '{{.Mountpoint}}' "$vol" 2>/dev/null || true)"
if [[ -n "$path" && -d "$path" ]]; then
  if namei -l "$path" 2>/dev/null | grep -q 'Permission denied'; then
    assert_fail "every directory above the uploads path is traversable" \
      "namei -l $path reports a directory the api cannot traverse"
  else
    assert_pass "every directory above the uploads path is traversable"
  fi

  mode="$(stat -c '%a' "$path")"
  if [[ "${mode: -1}" =~ ^[2367]$ ]]; then
    assert_fail "the uploads directory is not world-writable" \
      "mode is ${mode}: chmod 777 makes the upload work and gives every process on the host write access"
  else
    assert_pass "the uploads directory is not world-writable (mode ${mode})"
  fi
else
  assert_fail "the uploads volume was found" "docker volume inspect ${vol} returned nothing"
fi

uid="$(svc_compose stages exec -T "$(svc_name stages api)" id -u 2>/dev/null | tr -d '\r' || true)"
if [[ "$uid" == "0" ]]; then
  assert_fail "the api does not run as root" \
    "it is running as uid 0: making writes succeed by becoming root is not a fix"
elif [[ -n "$uid" ]]; then
  assert_pass "the api runs as a non-root uid (${uid})"
else
  assert_fail "the api's uid could be determined" "could not exec into the api service"
fi

assert_summary
