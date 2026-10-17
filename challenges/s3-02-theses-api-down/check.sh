#!/usr/bin/env bash
# s3-02 — check: the API is healthy AND the list returns rows. Connected to a
# database is not the same state as connected to the right database.
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
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

health="${NURSE_API:?set NURSE_API in lab.conf}"
list="${NURSE_LIST:?set NURSE_LIST in lab.conf}"

assert_http "the theses API is healthy" "$health" 200
assert_http "the list endpoint answers" "$list" 200

# The catalogue is intact: the list has to contain records, not merely respond.
rows="$(curl -fsS --max-time 15 "$list" 2>/dev/null \
        | grep -oE '"(id|numero)"' | wc -l || true)"
if (( rows > 0 )); then
  assert_pass "the list returns records ($rows on the first page)"
else
  assert_fail "the list returns records" \
    "the list endpoint answered but contained none — a reachable database is not the right database"
fi

assert_service "the api service is running" nurse api

# It survives the service being recreated, so the fix is in the environment
# file rather than in a container that happens to be running.
svc_compose nurse up -d --force-recreate "$(svc_name nurse api)" >/dev/null 2>&1 || true
assert_eventually "it is still healthy after the api is recreated" 90 \
  curl -fsS -o /dev/null --max-time 5 "$health"

assert_summary
