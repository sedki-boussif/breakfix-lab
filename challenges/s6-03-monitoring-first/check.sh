#!/usr/bin/env bash
# s6-03 — check: cause all three conditions and require an alert each time.
#
# This does not read the configuration and agree that it looks right. Rules are
# easy to write and easy to write wrongly, and a rule that cannot fire looks
# exactly like one that can. Every assertion here is positive: the condition is
# created, the alert is required, the condition is cleared.
#
# It is the most invasive check in the catalogue. Everything it disturbs is
# restored by an EXIT trap.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/fs.sh
. "$LAB_ROOT/lib/fs.sh"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

ID='s6-03-monitoring-first'
alog="${S6_03_ALERT_LOG:-/var/log/lab-monitor-alerts.log}"
reload="${S6_03_RELOAD:-}"
cert="${TLS_CERT:-/etc/nginx/tls/lab.crt}"
key="${TLS_KEY:-/etc/nginx/tls/lab.key}"
unit="${S6_03_STOP_UNIT:-${LEAVES_WEB_UNIT:-leaves.service}}"
fsname="${S6_03_DISK_FS:-monitor}"
fsmb="${S6_03_DISK_MB:-512}"
state="$(lab_state_dir "$ID")"
cert_backup="$state/tls-cert-backup"
stopped=0
fs_made=0
cert_swapped=0

restore() {
  if (( cert_swapped == 1 )) && [[ -s "$cert_backup" ]]; then
    lab_as_root cp -a "$cert_backup" "$cert" 2>/dev/null || true
    printf 'certificate restored from %s\n' "$cert_backup"
    lab_as_root systemctl reload "${NGINX_UNIT:-nginx.service}" >/dev/null 2>&1 || true
  fi
  if (( stopped == 1 )); then
    lab_as_root systemctl start "$unit" >/dev/null 2>&1 || true
  fi
  if (( fs_made == 1 )); then
    lab_fs_destroy "$fsname" >/dev/null 2>&1 || true
  fi
}
trap restore EXIT

alert_lines() { lab_as_root wc -l <"$alog" 2>/dev/null || echo 0; }

# wait_for_alert <description> <pattern> <seconds>
# Requires a NEW line matching the pattern. The baseline is taken by the caller
# immediately before causing the condition, so an alert already sitting in the
# log cannot be mistaken for this one.
wait_for_alert() {
  local desc="$1" pattern="$2" window="$3" baseline="$4"
  local waited=0 now fresh
  while (( waited < window )); do
    now="$(alert_lines)"
    if (( now > baseline )); then
      fresh="$(lab_as_root tail -n "$(( now - baseline ))" "$alog" 2>/dev/null || true)"
      if grep -qiE "$pattern" <<<"$fresh"; then
        assert_pass "${desc} (after ${waited}s)"
        return 0
      fi
    fi
    sleep 5; waited=$(( waited + 5 ))
  done
  now="$(alert_lines)"
  if (( now > baseline )); then
    assert_fail "$desc" \
      "${now} lines appeared in ${alog} in ${window}s but none matched /${pattern}/ — the alert fired and did not say what for, which during an incident is the same as not firing"
  else
    assert_fail "$desc" \
      "nothing was appended to ${alog} in ${window}s"
  fi
}

# --- the alert channel has to exist ---------------------------------------
if ! lab_as_root test -e "$alog"; then
  assert_fail "the alert log exists at ${alog}" \
    "whatever you built has to append its alerts here, one line each. A check cannot read a dashboard, and neither can anyone who is asleep"
  assert_summary
  exit $?
fi
assert_pass "the alert log exists at ${alog}"

[[ -z "$reload" ]] || lab_as_root bash -c "$reload" >/dev/null 2>&1 || true

# --- 0. quiet when nothing is wrong ---------------------------------------
# Monitoring that alerts constantly carries the same information as monitoring
# that never alerts, and it is also the control for everything below: if the
# log grows on its own, "a line appeared" proves nothing about the condition.
printf 'watching for 30s with nothing wrong...\n'
quiet_base="$(alert_lines)"
sleep 30
quiet_now="$(alert_lines)"
if (( quiet_now == quiet_base )); then
  assert_pass "it is quiet when nothing is wrong (control for the three below)"
else
  assert_fail "it is quiet when nothing is wrong" \
    "$(( quiet_now - quiet_base )) alert(s) appeared in 30 idle seconds. Beyond being noise, it makes the assertions below meaningless: a line appearing proves nothing if lines appear anyway. Last one: $(lab_as_root tail -1 "$alog" | cut -c1-80)"
fi

# --- 1. a filesystem over 80% --------------------------------------------
# A filesystem the monitoring has never seen, which is what "any filesystem"
# means. A rule hard-coded to / cannot pass this.
printf 'creating a %sMB filesystem and filling it past 80%%...\n' "$fsmb"
mnt="$(lab_fs_require "$fsname" "$fsmb" 2>/dev/null || true)"
if [[ -z "$mnt" ]] || ! lab_fs_is_ours "$mnt"; then
  assert_fail "a bounded filesystem could be created to test the disk alert" \
    "lab_fs_require ${fsname} ${fsmb} did not produce one of our loop mounts — lab doctor reports on LAB_SCRATCH_DIR"
else
  fs_made=1
  disk_base="$(alert_lines)"
  fill_k="$(lab_fs_fill_kb "$mnt" 88 "$fsmb")"
  lab_as_root dd if=/dev/zero of="$mnt/fill" bs=1K count="$fill_k" \
    status=none 2>/dev/null || true
  pct="$(lab_fs_pct "$mnt")"
  if [[ "${pct:-0}" -lt 81 ]]; then
    assert_fail "the test filesystem reached over 80%" \
      "it is at ${pct}% — the fill did not take, so the alert cannot be tested"
  else
    assert_pass "the test filesystem is at ${pct}% (${mnt})"
    wait_for_alert "a filesystem over 80% raises an alert" \
      "disk|filesystem|space|${fsname}|$(basename "$mnt")" 120 "$disk_base"

    recov_base="$(alert_lines)"
    lab_as_root rm -f "$mnt/fill"
    wait_for_alert "and it clears when the space comes back" \
      "resolv|recover|clear|ok|normal|disk|filesystem|space" 120 "$recov_base"
  fi
fi

# --- 2. a service down ----------------------------------------------------
printf 'stopping %s...\n' "$unit"
svc_base="$(alert_lines)"
stopped=1
lab_as_root systemctl stop "$unit" >/dev/null 2>&1 || true
if systemctl is-active --quiet "$unit"; then
  assert_fail "${unit} could be stopped to test the service alert" \
    "it is still active after systemctl stop, so this assertion would prove nothing either way"
else
  assert_pass "${unit} is stopped"
  short="${unit%.service}"
  wait_for_alert "a stopped service raises an alert naming it" \
    "${short}|service|unit|down" 150 "$svc_base"

  recov_base="$(alert_lines)"
  lab_as_root systemctl start "$unit" >/dev/null 2>&1 || true
  stopped=0
  assert_eventually "${unit} is back up" 90 systemctl is-active --quiet "$unit"
  wait_for_alert "and it clears when the service comes back" \
    "resolv|recover|clear|ok|up|${short}" 150 "$recov_base"
fi

# --- 3. a certificate expiring inside 14 days ----------------------------
if ! lab_as_root test -f "$cert"; then
  assert_fail "there is a certificate at ${cert} to test with" \
    "SETUP.md section 8 makes it; without one this alert cannot be exercised"
else
  lab_as_root cp -a "$cert" "$cert_backup"
  lab_as_root chown "$(id -u):$(id -g)" "$cert_backup" 2>/dev/null || true
  if ! lab_as_root test -s "$cert_backup"; then
    assert_fail "the real certificate could be copied aside first" \
      "refusing to swap a certificate this check cannot put back"
  else
    printf 'installing a certificate that expires in 7 days (yours is at %s)...\n' \
      "$cert_backup"
    cert_swapped=1
    cert_base="$(alert_lines)"
    tmpdir="$(lab_as_root mktemp -d)"
    if lab_as_root openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
         -subj "/CN=${LEAVES_VHOST:-conge.lab.invalid}" \
         -addext "subjectAltName=DNS:${STAGES_VHOST:-stages.lab.invalid},DNS:${LEAVES_VHOST:-conge.lab.invalid},DNS:${NURSE_VHOST:-theses.lab.invalid}" \
         -keyout "$tmpdir/short.key" -out "$tmpdir/short.crt" >/dev/null 2>&1; then
      lab_as_root cp "$tmpdir/short.crt" "$cert"
      # The key is left alone: the alert is about the certificate's dates, and
      # replacing a working key for a test is a larger blast radius than the
      # assertion needs. nginx keeps serving the old pair until reloaded.
      [[ -z "$reload" ]] || lab_as_root bash -c "$reload" >/dev/null 2>&1 || true
      wait_for_alert "a certificate inside 14 days raises an alert" \
        "cert|tls|expir|x509|days" 150 "$cert_base"
    else
      assert_fail "a short-lived certificate could be generated" \
        "openssl req failed; without one this alert cannot be exercised"
    fi
    lab_as_root rm -rf "$tmpdir" 2>/dev/null || true

    recov_base="$(alert_lines)"
    lab_as_root cp -a "$cert_backup" "$cert"
    cert_swapped=0
    lab_as_root systemctl reload "${NGINX_UNIT:-nginx.service}" >/dev/null 2>&1 || true
    [[ -z "$reload" ]] || lab_as_root bash -c "$reload" >/dev/null 2>&1 || true
    printf 'your certificate is back.\n'
    wait_for_alert "and it clears when a long-lived certificate returns" \
      "resolv|recover|clear|ok|cert|tls|expir" 150 "$recov_base"
  fi
fi

# --- and the applications are where we found them ------------------------
assert_http "stages still answers" "${STAGES_URL:?}" 200
assert_http "leaves still answers" "${LEAVES_URL:?}" 200
assert_http "the theses API still answers" "${NURSE_API:?}" 200

restore
assert_summary
