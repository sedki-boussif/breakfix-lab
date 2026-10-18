#!/usr/bin/env bash
# s9-01 — check: a hundred consecutive requests, all 200, and the upstream
# still has every member it started with. One successful request proves
# nothing here, which is the point of the challenge.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s9-01-one-request-in-five'
n="${S9_01_REQUESTS:-100}"
vhost="${NURSE_VHOST:-theses.lab.invalid}"
url="http://127.0.0.1/api/health/"
want_members="$(lab_state_get "$ID" MEMBERS 0)"

assert_cmd "the nginx configuration is valid" lab_as_root nginx -t

# The measurement, not a sample.
fails=0; codes=""
for _ in $(seq 1 "$n"); do
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: ${vhost}" "$url" || echo 000)"
  [[ "$c" == 200 ]] || { fails=$(( fails + 1 )); codes+="${c} "; }
done
if (( fails == 0 )); then
  assert_pass "${n} consecutive requests all returned 200"
else
  assert_fail "${n} consecutive requests all returned 200" \
    "${fails} of ${n} failed (${codes}) — run the loop yourself: a single request passes most of the time"
fi

# The capacity is still there: the passing fix repairs the member rather than
# deleting it.
if [[ "$want_members" != 0 ]]; then
  got="$(lab_as_root nginx -T 2>/dev/null | awk '/upstream[[:space:]]+theses_api/,/}/' \
         | grep -c '^[[:space:]]*server ' || true)"
  if [[ "${got:-0}" == 0 ]]; then
    printf 'SKIP  no theses_api upstream in the running config — acceptable if you removed it entirely, but say so in the report\n'
  else
    assert_equal "the upstream still has all ${want_members} members" "$got" "$want_members"
    # And every member actually has something listening on it.
    bad=""
    while read -r addr; do
      p="${addr##*:}"
      ss -ltnH "sport = :${p}" 2>/dev/null | grep -q . || bad+="${addr} "
    done < <(lab_as_root nginx -T 2>/dev/null | awk '/upstream[[:space:]]+theses_api/,/}/' \
             | sed -nE 's/^[[:space:]]*server[[:space:]]+([^;[:space:]]+).*/\1/p')
    if [[ -z "$bad" ]]; then
      assert_pass "every upstream member has a service listening on it"
    else
      assert_fail "every upstream member has a service listening on it" \
        "nothing is listening for: ${bad}"
    fi
  fi
fi

assert_summary
