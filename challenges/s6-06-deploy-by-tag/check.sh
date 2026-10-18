#!/usr/bin/env bash
# s6-06 — check: the script refuses a bad tag, the checkout is at a tag, the
# record matches reality, and the rollback is observable — proved by doing it
# twice and requiring the response to change and change back.
#
# The starting commit is restored by an EXIT trap: this check deploys other
# versions of a real application, and leaving the machine on the wrong one
# because an assertion misbehaved would be worse than not checking.
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

ID='s6-06-deploy-by-tag'
app="${S6_06_APP:-leaves}"
dirvar="$(printf '%s_DIR' "${app^^}")"
dir="${!dirvar:-/opt/$app}"
urlvar="$(printf '%s_URL' "${app^^}")"
app_url="${!urlvar:-}"
probe="${S6_06_PROBE_URL:-$app_url}"
script="${S6_06_DEPLOY_SCRIPT:-/usr/local/bin/deploy.sh}"
state="${S6_06_DEPLOY_STATE:-/var/lib/breakfix-lab/deployed-tags}"
# Where to put the machine back. Set once HEAD is confirmed to be at a tag;
# empty until then, which is also when nothing has been deployed yet.
restore_to=''

restore() {
  [[ -n "$restore_to" ]] || return 0
  printf 'putting %s back on %s...\n' "$app" "$restore_to"
  lab_as_root "$script" "$restore_to" >/dev/null 2>&1 ||
    git -C "$dir" checkout -q "$restore_to" 2>/dev/null || true
}
trap restore EXIT

# fingerprint — what the application is currently saying, normalised.
# CSRF tokens and session ids change on every request and would make any two
# responses differ; stripping long hex-ish runs removes them without hiding a
# real content change.
fingerprint() {
  curl -s --max-time 10 "$probe" 2>/dev/null |
    sed -E 's/[A-Za-z0-9_-]{24,}/TOKEN/g' |
    tr -d '[:space:]' | sha256sum | cut -c1-16
}

assert_file "a deploy script exists at ${script}" "$script"
if [[ ! -f "$script" ]]; then
  assert_summary
  exit $?
fi
assert_cmd "it is executable" test -x "$script"

# --- it never deploys with git pull ---------------------------------------
if grep -qE '(^|[^[:alnum:]_])git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?pull' "$script"; then
  assert_fail "the deploy script does not use git pull" \
    "$(grep -nE 'git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?pull' "$script" | sed -n 1p | cut -c1-70) — pull deploys whatever the branch is at now, which is not a version you can name, roll back to, or tell a colleague"
else
  assert_pass "the deploy script does not use git pull"
fi

# --- two tags, and the working tree is at one of them --------------------
if [[ ! -d "$dir/.git" ]]; then
  assert_fail "${dir} is a git checkout" "no .git — re-clone it"
  assert_summary
  exit $?
fi

mapfile -t tags < <(git -C "$dir" tag 2>/dev/null || true)
assert_above "the checkout has at least two tags" "${#tags[@]}" 1 " tags"

dirty="$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)"
assert_equal "the working tree is clean" "$dirty" "0"

head_sha="$(git -C "$dir" rev-parse HEAD)"
current_tag=''
for t in "${tags[@]}"; do
  [[ "$(git -C "$dir" rev-parse "${t}^{commit}" 2>/dev/null || true)" == "$head_sha" ]] || continue
  current_tag="$t"; break
done
if [[ -n "$current_tag" ]]; then
  assert_pass "HEAD is exactly a tag (${current_tag})"
  restore_to="$current_tag"
else
  assert_fail "HEAD is exactly a tag" \
    "HEAD is ${head_sha:0:8}, which is no tag's commit. 'Deployed' has to be a version with a name, or you cannot say what is running"
fi

# --- the record matches reality ------------------------------------------
if ! lab_as_root test -s "$state"; then
  assert_fail "the deploy record exists at ${state}" \
    "the script has to write what it deployed somewhere outside the checkout — git describe tells you what the tree is at now, which is a different question"
elif [[ -n "$current_tag" ]]; then
  recorded="$(lab_as_root grep -oE '[A-Za-z0-9._/-]+' "$state" | grep -Fx "$current_tag" | tail -1 || true)"
  if [[ -n "$recorded" ]]; then
    assert_pass "the deploy record names the tag that is checked out (${current_tag})"
  else
    assert_fail "the deploy record names the tag that is checked out" \
      "${state} does not mention ${current_tag}. A record that has drifted from reality is worse than no record, because it will be believed"
  fi
fi

# --- an unknown tag is refused, and changes nothing ----------------------
before_sha="$(git -C "$dir" rev-parse HEAD)"
assert_not "an unknown tag is refused" \
  lab_as_root "$script" 'v-does-not-exist-s6-06'
after_sha="$(git -C "$dir" rev-parse HEAD)"
assert_equal "and refusing it left the checkout alone" "$after_sha" "$before_sha"

# --- the rollback is observable ------------------------------------------
# A control first: if the response changes on its own, "it changed" proves
# nothing about the deployment, and this would be a check that always passes.
if [[ -z "$probe" ]]; then
  assert_fail "there is a URL to compare versions at" \
    "set ${urlvar} or S6_06_PROBE_URL in lab.conf"
elif [[ -z "$current_tag" || "${#tags[@]}" -lt 2 ]]; then
  printf 'SKIP  not at a tag, or fewer than two tags, so the rollback cannot be driven\n'
else
  fp_a="$(fingerprint)"
  sleep 2
  fp_a2="$(fingerprint)"
  if [[ -z "$fp_a" ]]; then
    assert_fail "the application answers at ${probe}" "nothing came back"
  elif [[ "$fp_a" != "$fp_a2" ]]; then
    assert_fail "the response is stable enough to detect a version change" \
      "two requests to ${probe} two seconds apart already differ, so 'it changed after the rollback' would prove nothing. Point S6_06_PROBE_URL at a page without a timestamp or a per-request token"
  else
    assert_pass "the response is stable between requests (control for the next assertion)"

    other=''
    for t in "${tags[@]}"; do
      [[ "$t" != "$current_tag" ]] && other="$t"
    done
    printf 'deploying %s with your script...\n' "$other"
    deploy_other=0
    lab_as_root "$script" "$other" >/dev/null 2>&1 || deploy_other=$?
    if (( deploy_other != 0 )); then
      assert_fail "the script deploys ${other}" "it exited ${deploy_other}"
    else
      assert_pass "the script deploys ${other}"
      assert_eventually "the application answers on ${other}" 90 \
        curl -fsS -o /dev/null --max-time 5 "$probe"
      fp_b="$(fingerprint)"
      if [[ "$fp_b" != "$fp_a" ]]; then
        assert_pass "the deployed version is visibly different (${fp_a} → ${fp_b})"
      else
        assert_fail "the deployed version is visibly different" \
          "${probe} says exactly the same thing on ${current_tag} and ${other}. The two tags need a difference the running application shows, or a rollback is something you can do and never confirm"
      fi

      printf 'rolling back to %s...\n' "$current_tag"
      roll=0
      lab_as_root "$script" "$current_tag" >/dev/null 2>&1 || roll=$?
      if (( roll != 0 )); then
        assert_fail "the rollback to ${current_tag} succeeds" "it exited ${roll}"
      else
        assert_eventually "the application answers after the rollback" 90 \
          curl -fsS -o /dev/null --max-time 5 "$probe"
        fp_c="$(fingerprint)"
        assert_equal "the rollback restored the earlier behaviour" "$fp_c" "$fp_a"
      fi
    fi
  fi
fi

# --- and the runbook says so ---------------------------------------------
report="$LAB_ROOT/reports/${ID}.md"
if [[ -f "$report" ]]; then
  if grep -qiE 'git pull' "$report"; then
    assert_fail "the report does not recommend git pull" \
      "it is mentioned in ${report} — if that is to explain why not, say so in those words"
  else
    assert_pass "the report does not recommend git pull"
  fi
  assert_file_matches "the report records the rollback and what it changed" \
    "$report" '[Rr]oll ?back|[Rr]olled back|previous tag'
else
  assert_fail "the report exists" \
    "lab report ${ID}   # the tag names, the visible difference, and the rollback"
fi

restore
restore_to=''
assert_summary
