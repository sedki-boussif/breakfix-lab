#!/usr/bin/env bash
# s7-06 — check: all four traces gone, the persistence genuinely unable to
# restore itself, and the report naming every one of the four.
#
# This removes nothing. It waits out the persistence window and looks again,
# because a cleanup that leaves the cron job passes a casual inspection.
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

ID='s7-06-someone-was-in-here'
user="$(lab_state_get "$ID" USER "${INTRUDER_USER:-svc-backup}")"
port="$(lab_state_get "$ID" PORT "${INTRUDER_PORT:-47113}")"
pub="$(lab_state_get "$ID" PUBKEY '')"
report="$LAB_ROOT/reports/${ID}.md"
wait_s="${S7_06_PERSIST_WAIT:-150}"

# 1. The account.
assert_not "the planted account is gone" id -u "$user"

# 2. The key, anywhere on the machine. Checked by its own content, so moving it
#    does not help.
# Match the key MATERIAL, not the algorithm name. "${pub%% *}" is the first
# field — ssh-ed25519 — which matches the owner's own key and would make this
# assertion fail for ever on any machine whose user has an ed25519 key. Found
# exactly that way.
key_material="$(printf '%s' "$pub" | cut -d' ' -f2)"
key_present() {
  [[ -n "$key_material" ]] || return 1
  local f
  # Named files only, and explicitly NOT the lab's own state directory, which
  # holds the planted key on purpose — a recursive grep over /root matched the
  # lab's own bookkeeping and failed a correct cleanup. /etc/ssh is included
  # because AuthorizedKeysFile can point there.
  while IFS= read -r f; do
    if lab_as_root grep -qF -- "$key_material" "$f" 2>/dev/null; then return 0; fi
  done < <(lab_as_root find /home /root /etc/ssh -name 'authorized_keys*' -type f \
             -not -path '*/.breakfix-progress/*' 2>/dev/null)
  return 1
}
assert_not "the intruder's key is not in any authorized_keys" key_present

# 3. The listener.
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
assert_not "nothing is listening on port ${port}" \
  bash -c 'ss -ltnH "sport = :$1" 2>/dev/null | grep -q .' _ "$port"

# 4. The persistence — and the part that matters: it cannot restore anything.
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
assert_cmd "no cron entry references the planted account" \
  bash -c '! grep -rqF -- "$1" /etc/cron.d /etc/crontab /etc/cron.hourly /var/spool/cron 2>/dev/null' _ "$user"

# Only worth waiting when there is nothing left to find: no point waiting to
# see whether something returns when it never left. This also keeps a failing
# run fast, which matters while you are iterating on a cleanup.
if (( ASSERT_FAILED > 0 )); then
  printf 'SKIP  the persistence window was not waited out: traces are still present above\n'
else
  printf 'waiting %ss for any persistence to fire before looking again...\n' "$wait_s"
  sleep "$wait_s"
  assert_not "the key has not come back after ${wait_s}s" key_present
  assert_not "the account has not come back" id -u "$user"
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
  assert_not "nothing started listening again on port ${port}" \
    bash -c 'ss -ltnH "sport = :$1" 2>/dev/null | grep -q .' _ "$port"
fi

# The deliverable is the list of what you found.
if [[ -f "$report" ]]; then
  found=0
  for pat in '[Aa]ccount|[Uu]ser' '[Kk]ey|authorized_keys' '[Cc]ron|[Tt]imer|persist' '[Ll]isten|[Pp]ort|[Pp]rocess'; do
    if grep -qE "$pat" "$report"; then found=$(( found + 1 )); fi
  done
  if (( found == 4 )); then
    assert_pass "the report names all four traces"
  else
    assert_fail "the report names all four traces" \
      "found ${found} of 4 in ${report}. The list of what you found IS the deliverable: it tells the next person whether you looked everywhere"
  fi
  assert_file_matches "the report says how each was found" \
    "$report" 'ss -ltnp|getent|crontab|/etc/cron|authorized_keys|lastlog|/proc/'
else
  assert_fail "the report exists" "lab report ${ID}   # all four traces, and how each was found"
fi

assert_summary
