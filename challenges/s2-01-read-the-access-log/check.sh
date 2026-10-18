#!/usr/bin/env bash
# s2-01 — check: compute all six answers from the log, and compare.
#
# On a wrong answer this says how it is wrong and never what the answer is:
# how many entries are off, which position first differs, whether a number is
# high or low. A check that prints the answer turns the second attempt into
# transcription, and the thing being learned is the pipeline, not the number.
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

ID='s2-01-read-the-access-log'
dir="${S2_01_DIR:-/var/tmp/lab-s2-01}"
log="$dir/access.log"
answers="$dir/answers.txt"

if [[ ! -s "$log" ]]; then
  printf 'No log at %s. Start the mission first: lab start %s\n' "$log" "$ID" >&2
  exit 1
fi
if [[ ! -s "$answers" ]]; then
  printf 'No answer sheet at %s. Start the mission first: lab start %s\n' "$answers" "$ID" >&2
  exit 1
fi

# given <key> — the value for a key, commas and spaces normalised away, so a
# "192.0.2.1, 192.0.2.2" is graded on its content rather than its spacing.
given() {
  sed -n "s/^${1}=//p" "$answers" | sed -n '1p' | tr -d '[:space:]'
}

# --- what the log actually says ---------------------------------------------
# Field positions in the combined format: 1 address, 4 "[timestamp", 7 path,
# 9 status, 10 body bytes.
# Every pipeline here ends in something that reads to the end of its input.
# `| head -10` would be the obvious spelling and is a trap: head exits early,
# sort takes SIGPIPE, and under `set -o pipefail` the command substitution
# fails and errexit takes the whole check with it — silently, before a single
# assertion prints. It needs 50,000 lines to show up, which is exactly the size
# of this log and not the size of anything else in the lab.
top_n_field() {         # top_n_field <field> <n>
  awk -v f="$1" '{print $f}' "$log" | sort | uniq -c | sort -rn -k1,1 \
    | awk -v n="$2" 'NR <= n {printf "%s%s", sep, $2; sep=","} END{print ""}'
}
count_at_rank() {       # count_at_rank <field> <rank>
  awk -v f="$1" '{print $f}' "$log" | sort | uniq -c | sort -rn -k1,1 \
    | awk -v r="$2" 'NR == r {print $1+0}'
}

want_ips="$(top_n_field 1 10)"
want_urls="$(top_n_field 7 10)"
want_status="$(awk '{print $9}' "$log" | sort -n | uniq -c \
  | awk '{printf "%s%s:%s", sep, $2, $1; sep=","} END{print ""}')"
want_5xx="$(awk '$9 >= 500 && $9 < 600 {split($4, a, ":"); print a[2]}' "$log" \
  | sort | uniq -c | awk '{printf "%s%s:%s", sep, $2, $1; sep=","} END{print ""}')"
want_404_ip="$(awk '$9 == 404 {print $1}' "$log" | sort | uniq -c | sort -rn -k1,1 \
  | awk 'NR == 1 {print $2}')"
want_bytes="$(awk '{s += $10} END {printf "%d", s}' "$log")"

# --- is the question gradeable at all? --------------------------------------
# A tie across the tenth and eleventh place would make two different answers
# equally correct, and marking one of them wrong would be the check's fault
# rather than the reader's. The generator avoids it; this proves it.
for spec in "1:addresses" "7:paths"; do
  field="${spec%%:*}"; what="${spec##*:}"
  tenth="$(count_at_rank "$field" 10)"
  eleventh="$(count_at_rank "$field" 11)"
  if [[ -n "$eleventh" ]] && (( tenth == eleventh )); then
    assert_fail "the top ten ${what} are unambiguous" \
      "tenth and eleventh place are tied on ${tenth} requests, so two answers are equally right. This is a fault in the generated log, not in your answer: rm -rf ${dir} and start the mission again"
  else
    assert_pass "the top ten ${what} are unambiguous (10th=${tenth}, 11th=${eleventh:-none})"
  fi
done

# --- grading ----------------------------------------------------------------
# compare_list <description> <got> <want> <unit>
# Reports the count wrong and the first position that differs. Never the value.
compare_list() {
  local desc="$1" got="$2" want="$3" unit="$4"
  local -a g w
  IFS=',' read -r -a g <<<"$got"
  IFS=',' read -r -a w <<<"$want"
  if [[ -z "$got" ]]; then
    assert_fail "$desc" "not answered"
    return 0
  fi
  if (( ${#g[@]} != ${#w[@]} )); then
    assert_fail "$desc" "${#g[@]} ${unit} given, ${#w[@]} wanted"
    return 0
  fi
  local i first=0 wrong=0
  for (( i = 0; i < ${#w[@]}; i++ )); do
    if [[ "${g[$i]}" != "${w[$i]}" ]]; then
      wrong=$(( wrong + 1 ))
      (( first != 0 )) || first=$(( i + 1 ))
    fi
  done
  if (( wrong == 0 )); then
    assert_pass "$desc"
  else
    assert_fail "$desc" \
      "${wrong} of ${#w[@]} wrong, first at position ${first}. Check the order as well as the membership — the ordering is the question"
  fi
}

# compare_number <description> <got> <want>
compare_number() {
  local desc="$1" got="$2" want="$3"
  if [[ -z "$got" ]]; then
    assert_fail "$desc" "not answered"
  elif [[ ! "$got" =~ ^[0-9]+$ ]]; then
    assert_fail "$desc" "'${got}' is not a whole number"
  elif [[ "$got" == "$want" ]]; then
    assert_pass "$desc"
  elif (( got > want )); then
    assert_fail "$desc" "too high — are you summing a column that includes something you did not mean to count?"
  else
    assert_fail "$desc" "too low — is the whole file being read, and is it the right column?"
  fi
}

compare_list "1. the ten addresses with the most requests" \
  "$(given top_ips)" "$want_ips" "addresses"
compare_list "2. the ten paths with the most requests" \
  "$(given top_urls)" "$want_urls" "paths"
compare_list "3. the count of every status code" \
  "$(given status_counts)" "$want_status" "codes"
compare_list "4. the 5xx responses per hour" \
  "$(given fivexx_by_hour)" "$want_5xx" "hours"

got_404="$(given top_404_ip)"
if [[ -z "$got_404" ]]; then
  assert_fail "5. the address responsible for the most 404s" "not answered"
elif [[ "$got_404" == "$want_404_ip" ]]; then
  assert_pass "5. the address responsible for the most 404s"
else
  assert_fail "5. the address responsible for the most 404s" \
    "not that one. It is not the busiest address overall, which is the point of the question: filter to the 404s first, then count"
fi

compare_number "6. the total bytes served" "$(given bytes_total)" "$want_bytes"

assert_summary
