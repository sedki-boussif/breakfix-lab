#!/usr/bin/env bash
# s4-07 — check: the CODE fails closed, not just this deployment's config.
# Setting the environment variables and calling it done does not pass.
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

dir="${NURSE_DIR:?}"
env_file="${NURSE_ENV:?}"
py="${dir}/.venv/bin/python"

# The deployment still works.
assert_http "the theses API answers" "${NURSE_API:?}" 200
assert_cmd "the nurse API service is running" systemctl is-active --quiet "${NURSE_API_UNIT:-nurse-api.service}"

# 1. With SECRET_KEY unset, the application must refuse to start. Run Django's
#    own checks with the variable removed from an otherwise complete
#    environment, so this tests the code rather than the unit file.
refuses_without_secret() {
  # shellcheck disable=SC2016  # the body runs in another shell, with its own $1..$3
  lab_as_root bash -c '
    set -a
    . "$1"
    set +a
    unset SECRET_KEY
    cd "$2" || exit 9
    "$3" manage.py check 2>&1
  ' _ "$env_file" "$dir" "$py"
}
out="$(refuses_without_secret || true)"
status=0; refuses_without_secret >/dev/null 2>&1 || status=$?
if (( status != 0 )); then
  if grep -qiE 'SECRET_KEY' <<<"$out"; then
    assert_pass "with SECRET_KEY unset it refuses to start, naming the variable"
  else
    assert_pass "with SECRET_KEY unset it refuses to start"
    printf '      note: the error does not mention SECRET_KEY, which makes it harder\n'
    printf '      to act on. Consider ImproperlyConfigured("SECRET_KEY is not set")\n'
  fi
else
  assert_fail "with SECRET_KEY unset it refuses to start" \
    "it started anyway, so the fallback is still in the code. Setting the variable in ${env_file} fixes this deployment and leaves the next one insecure"
fi

# 2. With it set, it works — which it must, or the fix is an outage.
# shellcheck disable=SC2016  # the body runs in another shell, with its own $1..$3
assert_cmd "with SECRET_KEY set, Django's checks pass" \
  lab_as_root bash -c 'set -a; . "$1"; set +a; cd "$2" && "$3" manage.py check' \
  _ "$env_file" "$dir" "$py"

# 3. DEBUG is false when unset — the default, not the configured value.
debug_when_unset() {
  # shellcheck disable=SC2016  # the body runs in another shell, with its own $1..$3
  lab_as_root bash -c '
    set -a
    . "$1"
    set +a
    unset DEBUG
    cd "$2" || exit 9
    "$3" -c "
import django, os
django.setup()
from django.conf import settings
print(\"DEBUG=%s\" % settings.DEBUG)
" 2>/dev/null
  ' _ "$env_file" "$dir" "$py"
}
d="$(debug_when_unset || true)"
case "$d" in
  *DEBUG=False*) assert_pass "DEBUG defaults to False when the variable is unset" ;;
  *DEBUG=True*)  assert_fail "DEBUG defaults to False when the variable is unset" \
                   "it is True by default: an unconfigured deployment serves tracebacks to anyone who causes a 500" ;;
  *)             assert_fail "DEBUG's default could be determined" \
                   "could not import settings without DEBUG set — run the command in the hints by hand" ;;
esac

# 4. And in the running deployment, observed from outside rather than read.
probe="${NURSE_API%/}/lab-probe-$(date +%s)/"
body="$(curl -sS --max-time 10 "$probe" 2>/dev/null || true)"
if grep -qiE 'DEBUG = True|tried these URL patterns|Django tried' <<<"$body"; then
  assert_fail "the running deployment does not serve debug pages" \
    "a missing URL returned a Django debug page"
else
  assert_pass "the running deployment does not serve debug pages"
fi

# 5. A diff you would merge.
if lab_as_root git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  changed="$(lab_as_root git -C "$dir" diff --name-only | grep -c . || true)"
  lines="$(lab_as_root git -C "$dir" diff --numstat | awk '{a+=$1+$2} END{print a+0}')"
  if (( changed > 0 && changed <= 3 && lines <= 60 )); then
    assert_pass "the diff is small (${changed} file(s), ${lines} changed lines)"
  elif (( changed == 0 )); then
    printf 'SKIP  no uncommitted diff — already committed? then check it by hand: git -C %s log -1 -p\n' "$dir"
  else
    assert_fail "the diff is small" \
      "${changed} files and ${lines} lines: this is a real patch to a public repository, so keep it to the settings"
  fi
else
  printf 'SKIP  %s is not a git checkout, so the diff was not measured\n' "$dir"
fi

assert_summary
