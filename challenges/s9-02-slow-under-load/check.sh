#!/usr/bin/env bash
# s9-02 — check: p95 under a stated threshold at a stated concurrency, measured
# rather than felt, and the report carrying both numbers.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/load.sh
. "$LAB_ROOT/lib/load.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s9-02-slow-under-load'
url="${NURSE_API:?}"
conc="${S9_02_CONCURRENCY:-20}"
secs="${S9_02_DURATION:-20}"
p95_max="${S9_02_P95_MAX:-1.0}"
report="$LAB_ROOT/reports/${ID}.md"

assert_http "the API answers at all" "$url" 200

# One at a time, which is what every manual test measures.
printf 'measuring at concurrency 1 for 10s...\n'
one="$(lab_load_run "$url" 1 10)"
printf '  %s\n' "$one"

printf 'measuring at concurrency %s for %ss...\n' "$conc" "$secs"
many="$(lab_load_run "$url" "$conc" "$secs")"
printf '  %s\n' "$many"

p95="$(sed -n 's/.*p95=\([0-9.]*\).*/\1/p' <<<"$many")"
err="$(sed -n 's/.*error_rate=\([0-9.]*\).*/\1/p' <<<"$many")"

assert_below "p95 at concurrency ${conc} is under ${p95_max}s" "${p95:-99}" "$p95_max" "s"
assert_below "the error rate under load is near zero" "${err:-1}" 0.02

# Both numbers in the report, because "it feels better" is how this recurs.
if [[ -f "$report" ]]; then
  assert_file_matches "the report records a before and an after measurement" \
    "$report" 'p95|before|after'
  assert_file_matches "the report says which limit was binding" \
    "$report" '[Ww]orker|max_connections|pool|[Cc]oncurrenc'
  assert_file_matches "the report says what the new limit costs" \
    "$report" 'memory|RAM|cost|MB'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the measurements are the point, not the fix"
fi

assert_summary
