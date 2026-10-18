# s7-01 — Backups worth having

## The goal
Backups that would get the lab back, rather than backups that exist: off this
machine, encrypted, pruned, scheduled, monitored, and with a fingerprint so a
restore can be checked against what was actually in them.

## What I built

```bash
# 1. The password, outside the repository. A repository that carries its own
#    key is not encrypted in any useful sense.
sudo install -d -m 700 /etc/lab-backup
openssl rand -hex 32 | sudo tee /etc/lab-backup/password >/dev/null
sudo chmod 600 /etc/lab-backup/password

# 2. Two repositories: local for speed, off-site for survival.
sudo restic init -r /var/backups/lab/repo      --password-file /etc/lab-backup/password
sudo restic init -r /srv/lab-offsite/repo      --password-file /etc/lab-backup/password
```

The backup script, `/usr/local/sbin/lab-backup`:

```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit
PW=/etc/lab-backup/password
LOCAL=/var/backups/lab/repo
REMOTE=/srv/lab-offsite/repo
STAGE=/var/backups/lab/staging

mkdir -p "$STAGE"
# Databases as dumps. A copied data directory from a running server is not a
# backup, it is a corrupt data directory with a timestamp.
sudo -u postgres pg_dump leaves > "$STAGE/leaves.sql"
sudo -u postgres pg_dump nurse  > "$STAGE/nurse.sql"
( cd /opt/stages && docker compose exec -T db \
    pg_dump -U stages_owner stages ) > "$STAGE/stages.sql"

# The fingerprint, taken at backup time, beside the data it describes.
{
  printf 'taken=%s\n' "$(date -Is)"
  ( cd /opt/stages && docker compose exec -T db psql -tAq -U stages_owner -d stages \
      -c "SELECT 'trainees='||count(*) FROM trainees
          UNION ALL SELECT 'placements='||count(*) FROM placements
          UNION ALL SELECT 'audit_log='||count(*) FROM audit_log" )
} > /var/backups/lab/row-counts.txt

UPLOADS="$(docker volume inspect -f '{{.Mountpoint}}' stages_uploads)"
restic -r "$LOCAL" --password-file "$PW" backup \
  "$STAGE" "$UPLOADS" /var/backups/lab/row-counts.txt /etc/leaves /etc/nurse
restic -r "$LOCAL" --password-file "$PW" forget --keep-daily 7 --keep-weekly 4 --prune
restic -r "$LOCAL" --password-file "$PW" copy --repo2 "$REMOTE" --password-file2 "$PW"

# The marker is written LAST and only on success. A marker written first, or
# unconditionally, is the fault in s7-05.
date -Is > /var/backups/lab/last-success
```

Then two timers: `lab-backup.timer` (`OnCalendar=daily`, `Persistent=true`) and
`lab-backup-watch.timer` every fifteen minutes, whose service is six lines:

```bash
#!/usr/bin/env bash
set -euo pipefail
M=/var/backups/lab/last-success
AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$M" 2>/dev/null || echo 0) ) / 3600 ))
if (( AGE_H > 30 )); then
  printf '%s BACKUP STALE: last success %sh ago\n' "$(date -Is)" "$AGE_H" \
    >> /var/log/lab-backup-alerts.log
fi
```

## Verification
`restic snapshots` on the off-site repository lists snapshots; `restic
snapshots` with a wrong password fails; the off-site path is on a different
filesystem than the local one (`findmnt --target`); the snapshot count stays
within the retention policy; the timer is enabled; the fingerprint has row
counts in it. And the dead-man's-switch: stop the timer, backdate the marker,
and a line appears in the alert log.

## What this protects against, and what it does not
It survives a full local disk, a deleted local repository, and a corrupted local
snapshot — which is precisely s7-03. It does **not** survive the machine: the
off-site copy is a separate filesystem on the same host, because this lab makes
no network calls. On a real deployment that is an S3 bucket, a Borg server, or
another box, and the only line that changes is the `copy --repo2` target.

It also does not survive an attacker with root, who can delete both
repositories. That is s7-04.

## What I did not know before this
That the marker has to be written **last and only on success**, and that this
one detail is the difference between monitoring and theatre. Also that `restic
copy` deduplicates against the destination, so copying to the off-site
repository costs only the new data — which makes "3-2-1" affordable rather than
aspirational.
