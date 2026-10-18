#!/usr/bin/env bash
# s6-02 — reset: nothing is undone automatically. Unwinding a containerisation
# means deciding which copy of the data is now authoritative, and a script that
# guessed would be the most destructive thing in this repository.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s6-02-containerise-leaves'
dir="${LEAVES_DIR:-/opt/leaves}"
unit="${LEAVES_WEB_UNIT:-leaves.service}"
project="${LEAVES_PROJECT:-leaves}"

cat <<TXT
Nothing undone. There are now potentially two copies of the leaves data — the
host database and the volume — and only you know which one is current. A reset
script that picked for you would be the most destructive thing in this
repository.

To go back to systemd yourself, in this order:

  cd ${dir}
  sudo docker compose down              # NOT -v: that destroys the volume
  sudo systemctl enable --now ${unit}
  curl -fsS -o /dev/null -w '%{http_code}\\n' ${LEAVES_URL:-http://127.0.0.1:8081/}
  # then set LEAVES_MODE="systemd" in lab.conf

If the container's data is the copy you want to keep, dump it out first — while
the project is still up:

  cd ${dir}
  sudo docker compose exec -T ${DB_SERVICE:-db} \\
    pg_dump -U ${LEAVES_DB_ROLE:-leaves_app} ${LEAVES_DB_NAME:-leaves} > /var/tmp/${project}-from-container.sql

The recorded pre-move row count has been kept, so the check can still compare
against it if you try again.
TXT
lab_state_set "$ID" BROKEN_AT 0
