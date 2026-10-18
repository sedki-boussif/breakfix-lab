#!/usr/bin/env bash
# s9-04 — break: the service exits every couple of minutes and the restart
# policy brings it straight back, so it is up whenever anyone looks.
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

ID='s9-04-the-flapping-service'
unit="$(svc_name leaves web)"
every="${S9_04_INTERVAL:-110}"

if [[ "$(svc_mode leaves)" != "systemd" ]]; then
  printf 'this challenge needs LEAVES_MODE=systemd (restart accounting is the fault)\n' >&2
  exit 1
fi

# A timer that kills the service's main process periodically. The service's own
# Restart=on-failure does the rest, which is what makes it invisible.
lab_as_root tee /etc/systemd/system/lab-s9-04-flap.service >/dev/null <<UNIT
[Unit]
Description=Session cache maintenance
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'p=\$(systemctl show -p MainPID --value ${unit}); [ "\$p" != 0 ] && kill -9 "\$p" || true'
UNIT
lab_as_root tee /etc/systemd/system/lab-s9-04-flap.timer >/dev/null <<UNIT
[Unit]
Description=Session cache maintenance schedule
[Timer]
OnBootSec=${every}
OnUnitActiveSec=${every}
AccuracySec=1s
[Install]
WantedBy=timers.target
UNIT

lab_as_root systemctl daemon-reload
lab_as_root systemctl enable --now lab-s9-04-flap.timer >/dev/null 2>&1 || true
lab_as_root systemctl reset-failed "$unit" >/dev/null 2>&1 || true
svc_restart leaves web >/dev/null 2>&1 || true

lab_state_set "$ID" TIMER 'lab-s9-04-flap.timer'
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
