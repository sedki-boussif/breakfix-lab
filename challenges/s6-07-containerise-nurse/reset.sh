#!/usr/bin/env bash
# s6-07 — reset: as with s6-02, nothing is undone. There are now two possible
# copies of the theses data and only the person who moved it knows which is
# current.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-07-containerise-nurse'
dir="${NURSE_DIR:-/opt/nurse}"
unit="${NURSE_API_UNIT:-nurse-api.service}"

# The override file the check plants is removed by the check itself either way;
# this catches an interrupted run.
lab_as_root rm -f "$dir/compose.override.yaml" 2>/dev/null || true

cat <<TXT
Nothing undone. Two copies of the theses data may now exist — the host database
and the volume — and only you know which is current.

To go back to systemd yourself:

  cd ${dir}
  sudo docker compose down              # NOT -v: that destroys the volume
  sudo systemctl enable --now ${unit}
  curl -fsS -o /dev/null -w '%{http_code}\\n' ${NURSE_API:-http://127.0.0.1:8000/api/health/}
  # then in lab.conf: NURSE_MODE="systemd" and NURSE_ENV back to
  # ${NURSE_ENV:-/etc/nurse/nurse.env}

Remember the frontend too. Under systemd it is static files served by the host
nginx from the built dist/ — if you deleted that directory when you
containerised, rebuild it before expecting port 3000 to answer.

Any compose.override.yaml left behind by an interrupted check has been removed.
The recorded pre-move row count is kept.
TXT
lab_state_set "$ID" BROKEN_AT 0
