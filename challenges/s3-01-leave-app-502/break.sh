#!/usr/bin/env bash
# s3-01 — break: the gunicorn unit is told to exec a binary that is not there,
# so the service dies at startup and nginx reports 502. In compose mode, an
# override names a WSGI module that does not exist.
#
# Idempotent: only an ExecStart whose binary currently exists gets rewritten.
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/svc.sh
. "$LAB_ROOT/lib/svc.sh"

ID='s3-01-leave-app-502'
unit="$(svc_name leaves web)"

if [[ "$(svc_mode leaves)" == "systemd" ]]; then
  unit_path="$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null || true)"
  [[ -n "$unit_path" && -f "$unit_path" ]] || unit_path="/etc/systemd/system/${unit}"
  [[ -f "$unit_path" ]] || { printf 'cannot find the unit file for %s\n' "$unit" >&2; exit 1; }
  lab_backup_file "$ID" "$unit_path"

  exec_path="$(awk -F= '/^ExecStart=/{print $2; exit}' "$unit_path" | awk '{print $1}')"
  if [[ -n "$exec_path" && -x "$exec_path" ]]; then
    # The shape a rebuilt virtualenv leaves behind: one missing dot.
    broken="${exec_path/\/.venv\//\/venv\/}"
    [[ "$broken" != "$exec_path" ]] || broken="${exec_path}3"
    lab_as_root sed -i "s|^ExecStart=${exec_path}|ExecStart=${broken}|" "$unit_path"
    lab_state_set "$ID" BROKEN_PATH "$broken"
  fi

  # daemon-reload on its own changes nothing that is already running, which is
  # the whole reason this kind of fault surfaces hours later. The restart is
  # what makes it visible now.
  lab_as_root systemctl daemon-reload
  lab_as_root systemctl restart "$unit" >/dev/null 2>&1 || true
else
  override="${LEAVES_DIR:?}/compose.override.yaml"
  if [[ -f "$override" ]]; then
    lab_backup_file "$ID" "$override"
  else
    lab_state_set "$ID" CREATED_OVERRIDE 1
  fi
  cat >"$override" <<YAML
services:
  ${unit}:
    command: ["gunicorn", "--bind", "0.0.0.0:8081", "leave_management_project.wsgi_prod:application"]
YAML
  svc_compose leaves up -d "$unit" >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
