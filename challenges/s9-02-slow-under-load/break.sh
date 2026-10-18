#!/usr/bin/env bash
# s9-02 — break: starve the API's worker pool. One worker serves one request at
# a time, so everything is fine until there is more than one person.
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

ID='s9-02-slow-under-load'

if [[ "$(svc_mode nurse)" == "systemd" ]]; then
  unit="${NURSE_API_UNIT:-nurse-api.service}"
  dir="/etc/systemd/system/${unit}.d"
  exec_line="$(systemctl show -p ExecStart --value "$unit" 2>/dev/null \
               | sed -nE 's/.*argv\[\]=([^;]*).*/\1/p' | head -1 || true)"
  [[ -n "$exec_line" ]] || exec_line="$(awk -F= '/^ExecStart=/{print substr($0, index($0,"=")+1)}' \
                                        "/etc/systemd/system/${unit}" 2>/dev/null | head -1)"
  [[ -n "$exec_line" ]] || { printf 'cannot read ExecStart for %s\n' "$unit" >&2; exit 1; }
  starved="$(sed -E 's/--workers[= ]+[0-9]+/--workers 1/' <<<"$exec_line")"
  lab_as_root mkdir -p "$dir"
  printf '[Service]\nExecStart=\nExecStart=%s\n' "$starved" |
    lab_as_root tee "${dir}/91-lab.conf" >/dev/null
  lab_state_set "$ID" DROPIN "${dir}/91-lab.conf"
  lab_as_root systemctl daemon-reload
  svc_restart nurse api >/dev/null 2>&1 || true
else
  override="${NURSE_DIR:?}/compose.override.yaml"
  [[ ! -f "$override" ]] || lab_backup_file "$ID" "$override"
  printf 'services:\n  %s:\n    command: ["gunicorn", "--workers", "1", "--bind", "0.0.0.0:8000", "config.wsgi:application"]\n' \
    "$(svc_name nurse api)" >"$override"
  lab_state_set "$ID" OVERRIDE "$override"
  svc_compose nurse up -d --force-recreate "$(svc_name nurse api)" >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
