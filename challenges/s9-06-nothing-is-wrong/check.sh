#!/usr/bin/env bash
# s9-06 — check: health proven, and a report that says "no fault found" with
# the evidence to defend it. There is nothing to fix; the deliverable is the
# conclusion.
set -euo pipefail
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

ID='s9-06-nothing-is-wrong'
report="$LAB_ROOT/reports/${ID}.md"

# The same definition of healthy that lab chaos --check uses.
health_check

# And response time, because that is what was actually reported.
for pair in "stages ${STAGES_URL:-}" "leaves ${LEAVES_URL:-}" "nurse ${NURSE_API:-}"; do
  name="${pair%% *}"; url="${pair#* }"
  [[ -n "$url" ]] || continue
  t="$(curl -sS -o /dev/null -w '%{time_total}' --max-time 10 "$url" 2>/dev/null || echo 99)"
  assert_below "${name} responds quickly" "$t" 1.0 "s"
done

# The deliverable.
if [[ ! -f "$report" ]]; then
  assert_fail "the report exists" \
    "lab report ${ID}   # the conclusion IS the work here"
else
  if grep -qiE 'no fault found|nothing is wrong|no fault|healthy|not reproduce' "$report"; then
    assert_pass "the report concludes no fault was found"
  else
    assert_fail "the report concludes no fault was found" \
      "say it explicitly. If you concluded there IS a fault, this challenge is a no-op — the evidence is in challenges/${ID}/notes.md"
  fi
  assert_file_matches "the report carries measurements, not impressions" \
    "$report" '[0-9]+(\.[0-9]+)? ?(s|ms|%|MB|kB)'
  assert_file_matches "the report says what would have indicated a fault" \
    "$report" 'would have|if there were|threshold|expected|indicat'
  assert_file_matches "the report says what was NOT ruled out" \
    "$report" 'not rule|her (network|machine|connection)|outside|intermittent|cannot rule'
fi

assert_summary
