#!/usr/bin/env bash
# s3-04 — check: a real stylesheet is served with the right content type, and
# DEBUG is still off. Turning DEBUG on fixes the look and fails this check.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

url="${LEAVES_URL:?}"
css="${url%/}/${LEAVES_CSS:?set LEAVES_CSS in lab.conf}"

assert_http        "the page itself still answers" "$url" 200
assert_http        "the stylesheet is served" "$css" 200
assert_http_header "the stylesheet is served as CSS, not as an error page" \
                   "$css" '^content-type:[[:space:]]*text/css'

# DEBUG=True would serve static files itself and make the page look right. A
# URL that cannot exist tells us which mode the app is in, without reading a
# file: with DEBUG on, Django returns its own page listing the URL patterns.
probe="${url%/}/lab-probe-$(date +%s)/"
body="$(curl -sS --max-time 10 "$probe" 2>/dev/null || true)"
if grep -qiE 'DEBUG = True|tried these URL patterns|Django tried' <<<"$body"; then
  assert_fail "DEBUG is off" \
    "the app returned a Django debug page: static files are being served by DEBUG mode, not by WhiteNoise"
else
  assert_pass "DEBUG is off (a missing URL returns a plain error, not a debug page)"
fi

assert_summary
