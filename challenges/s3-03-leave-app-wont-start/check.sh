#!/usr/bin/env bash
# s3-03 — check: the app answers, and the secret is a real secret, in the file
# the service manager actually reads. Both wrong fixes are invisible from the
# outside, which is why this check reads the file.
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

url="${LEAVES_URL:?}"
env_file="${LEAVES_ENV:?}"

assert_service "the leave service is running" leaves web
assert_http    "the leave app answers" "$url" 200

secret="$(lab_as_root grep -m1 '^SECRET_KEY=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
secret="${secret%\"}"; secret="${secret#\"}"

if [[ -n "$secret" ]]; then
  assert_pass "SECRET_KEY is set in $(basename "$env_file")"
else
  assert_fail "SECRET_KEY is set in $(basename "$env_file")" \
    "not present in the file the unit reads — a value hard-coded in settings.py starts the app and breaks the next deploy"
fi

if (( ${#secret} >= 40 )); then
  assert_pass "SECRET_KEY is long enough (${#secret} characters)"
else
  assert_fail "SECRET_KEY is long enough" "${#secret} characters, want at least 40"
fi

# A value that exists anywhere in the application's own tree has been published.
if [[ -z "$secret" ]]; then
  assert_fail "SECRET_KEY is not a value shipped in the repo" \
    "there is no value to check"
elif grep -rqF -- "$secret" "${LEAVES_DIR:?}" 2>/dev/null; then
  assert_fail "SECRET_KEY is not a value shipped in the repo" \
    "this value appears inside ${LEAVES_DIR} — generate a new one: openssl rand -hex 32"
else
  assert_pass "SECRET_KEY is not a value shipped in the repo"
fi

svc_restart leaves web >/dev/null 2>&1 || true
assert_eventually "it answers again after a full restart" 45 \
  curl -fsS -o /dev/null --max-time 5 "$url"

assert_summary
