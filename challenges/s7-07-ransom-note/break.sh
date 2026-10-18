#!/usr/bin/env bash
# s7-07 — break: the uploads volume is scrambled, a ransom note is left, and
# the local backup repository is deleted. The off-site copy is untouched,
# because that is the way back.
#
# This cannot be undone. It asks first.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s7-07-ransom-note'
vol="${STAGES_UPLOADS_VOLUME:-stages_uploads}"
repo="${BACKUP_REPO:?}"; remote="${BACKUP_REMOTE:?}"; pw="${BACKUP_PASSWORD_FILE:?}"

lab_require_confirm 'yes-i-have-a-snapshot' \
  "$(cat <<'TXT'
This destroys the uploads volume. reset.sh cannot bring the files back: the
only route home is the off-site backup, which is the exercise.

You need, before continuing:
  - a snapshot of this VM that you can roll back to
  - an off-site repository from s7-01 that actually has the uploads in it
TXT
)"

# Refuse unless the way back exists. A drill with no recovery path is just loss.
if ! lab_as_root restic -r "$remote" --password-file "$pw" snapshots >/dev/null 2>&1; then
  printf 'refusing: the off-site repository at %s is not readable.\n' "$remote" >&2
  printf 'Finish s7-01 first — this challenge removes the local copy.\n' >&2
  exit 1
fi

path="$(lab_as_root docker volume inspect -f '{{.Mountpoint}}' "$vol" 2>/dev/null || true)"
[[ -n "$path" && -d "$path" ]] || { printf 'cannot find the uploads volume %s\n' "$vol" >&2; exit 1; }
case "$path" in
  /|/var|/var/lib|/home|/srv|/etc) printf 'refusing: %s is not a volume path\n' "$path" >&2; exit 1 ;;
esac

# Keep the local repository, so reset can restore the lab's own state.
if [[ -d "$repo" && -z "$(lab_state_get "$ID" LOCAL_ARCHIVE '')" ]]; then
  arch="$(lab_state_dir "$ID")/local-repo.tar"
  lab_as_root tar -cf "$arch" -C "$repo" . 2>/dev/null || true
  lab_as_root chown "$(id -u):$(id -g)" "$arch"
  lab_state_set "$ID" LOCAL_ARCHIVE "$arch"
fi

# Scramble: random name, random contents. The files are genuinely gone.
n=0
while IFS= read -r -d '' f; do
  lab_as_root dd if=/dev/urandom of="$f" bs=1k count=4 status=none 2>/dev/null || true
  lab_as_root mv "$f" "${path}/$(openssl rand -hex 8).locked" 2>/dev/null || true
  n=$(( n + 1 ))
done < <(lab_as_root find "$path" -maxdepth 1 -type f ! -name '*.locked' -print0 2>/dev/null)

lab_as_root tee "${path}/READ_ME_TO_RECOVER.txt" >/dev/null <<'NOTE'
                    YOUR FILES HAVE BEEN ENCRYPTED

All documents on this host have been encrypted with a unique key.
Your backups have been removed.

To recover your files, send 0.35 BTC to the address below and email
the reference with your transaction id.

    [address redacted by the lab - this is a drill]
    reference: 7f3c91

You have 72 hours. After that the key is destroyed.

Do not restart the server. Do not contact your provider.
NOTE

# And the local repository, as the note claims.
lab_as_root rm -rf "$repo"

lab_state_set "$ID" PATH_ "$path"
lab_state_set "$ID" SCRAMBLED "$n"
lab_state_set "$ID" BROKEN_AT "$(date +%s)"
