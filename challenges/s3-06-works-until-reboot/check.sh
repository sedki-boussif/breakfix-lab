#!/usr/bin/env bash
# s3-06 — check, in two phases, because the only honest test of "it survives a
# reboot" is a reboot.
#
#   check.sh --arm   record the boot id, then reboot the VM
#   check.sh         assert it came back unaided
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

ID='s3-06-works-until-reboot'
armed="$(lab_state_dir "$ID")/armed"
boot_id="$(cat /proc/sys/kernel/random/boot_id)"

if [[ "${1:-}" == "--arm" ]]; then
  printf '%s\n' "$boot_id" >"$armed"
  printf 'Armed. Now reboot the VM with sudo reboot, wait for it, touch nothing,\n'
  printf 'and run: lab check %s\n' "$ID"
  exit 0
fi

if [[ ! -f "$armed" ]]; then
  printf 'Not armed yet. This challenge is proved across a reboot:\n'
  printf '  lab check %s --arm\n  sudo reboot\n  lab check %s\n' "$ID" "$ID"
  exit 1
fi

if [[ "$(cat "$armed")" == "$boot_id" ]]; then
  assert_fail "the VM has been rebooted since arming" \
    "the boot id has not changed — reboot, then run this again without --arm"
  assert_summary
  exit $?
fi
assert_pass "the VM has been rebooted since arming"

assert_eventually "the theses API answers after the reboot, unaided" 120 \
  curl -fsS -o /dev/null --max-time 5 "${NURSE_API:?}"
assert_eventually "the theses site answers after the reboot, unaided" 120 \
  curl -fsS -o /dev/null --max-time 5 "${NURSE_WEB:?}"

# Came up *with* the machine, not by hand afterwards: compare the service's
# start time against the boot time.
booted="$(date -d "$(uptime -s)" +%s)"
if [[ "$(svc_mode nurse)" == "compose" ]]; then
  cid="$(svc_compose nurse ps -q "$(svc_name nurse api)" 2>/dev/null | head -1 || true)"
  started="$(lab_as_root docker inspect -f '{{.State.StartedAt}}' "$cid" 2>/dev/null || true)"
  policy="$(lab_as_root docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$cid" 2>/dev/null || true)"
  case "$policy" in
    always|unless-stopped) assert_pass "the restart policy will survive the next reboot ($policy)" ;;
    *) assert_fail "the restart policy will survive the next reboot" \
         "policy is '${policy:-none}': set unless-stopped in the compose file, not on the container" ;;
  esac
else
  assert_cmd "the nurse units are enabled at boot" \
    systemctl is-enabled --quiet "$(svc_name nurse api)"
  started="$(systemctl show -p ActiveEnterTimestamp --value "$(svc_name nurse api)" 2>/dev/null || true)"
fi

if [[ -n "${started:-}" ]]; then
  start_s="$(date -d "$started" +%s 2>/dev/null || echo 0)"
  delta=$(( start_s - booted ))
  if (( start_s > 0 && delta >= -30 && delta <= 300 )); then
    assert_pass "it started with the machine (${delta}s after boot)"
  else
    assert_fail "it started with the machine" \
      "it started ${delta}s after boot — that is a hand-started service, not one that came back on its own"
  fi
else
  assert_fail "the service's start time could be read" "nothing to compare against boot time"
fi

rm -f "$armed"
assert_summary
