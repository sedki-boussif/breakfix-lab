# s8-02 — Disaster recovery day

## The goal
Delete the VM. Rebuild it from the Git repository and the backups alone, inside
the recovery time objective written down in s7-02, and prove the data that came
back is the data that was there.

## Before the deletion — the three checks that make it a drill

```bash
# 1. The archive answers, and holds something.
sudo restic -r "$BACKUP_REMOTE" --password-file "$BACKUP_PASSWORD_FILE" snapshots

# 2. It is not on the disk that is about to be deleted.
findmnt --target "$BACKUP_REMOTE"          # must not be /

# 3. The key to it exists somewhere other than this VM.
#    This is the one that bites: s7-01 deliberately keeps the password out of
#    the repository, so it is also out of the backups.
ls -l "$BACKUP_PASSWORD_FILE"              # and: is this file anywhere else?

lab start s8-02-disaster-recovery          # writes the record; copy it off
scp ~/.breakfix-progress/state/s8-02-disaster-recovery/pre-destruction-record.txt \
    you@your-laptop:
```

Then note the wall-clock time and delete the VM, disk and all.

## The rebuild

s8-01's order, with step 6 replaced. Everything else is identical, which is the
point: the runbook you wrote after s8-01 is the artefact under test.

```bash
# New VM, bare Ubuntu 24.04. Then, from the Git repository:
git clone <your repo> breakfix-lab
cp lab.conf.example lab.conf     # or restore your own lab.conf from the repo

# Steps 1 to 5 of s8-01: account, keys, hardened SSH, firewall, Docker, apps.

# Step 6, replaced: restore the data rather than seed it.
sudo restic -r "$BACKUP_REMOTE" --password-file "$BACKUP_PASSWORD_FILE" snapshots
sudo restic -r "$BACKUP_REMOTE" --password-file "$BACKUP_PASSWORD_FILE" \
     restore latest --target /var/tmp/recover
sudo cat /var/tmp/recover"$BACKUP_FINGERPRINT"     # what the counts should be

# Databases: load the dump, never restore over a running data directory.
sudo -u postgres createdb stages
gunzip -c /var/tmp/recover/.../stages.sql.gz | sudo -u postgres psql -d stages
# Files: the uploads volume, back where it came from.
sudo rsync -aHAX --numeric-ids /var/tmp/recover/"$UPLOADS_PATH"/ "$UPLOADS_PATH"/

# Steps 7 onward: nginx with TLS, backups running again, monitoring.
# Then the two lists in lab.conf, and:
lab check s8-02-disaster-recovery --arm
sudo reboot
lab check s8-02-disaster-recovery --minutes <elapsed>
```

## What goes wrong, in the order it usually goes wrong

| Minute | What happens | What it really was |
|---|---|---|
| 5 | `restic snapshots` asks for a password you do not have | The password file lived only on the deleted VM. The archive is intact and unreadable, which is the same as gone |
| 20 | The apps come up but every page 502s | nginx was configured before the upstreams existed. Order, again |
| 40 | Row counts come back short | Not a broken restore — the archive is older than the rows. This is the loss window, and it is a number to record, not a bug to chase |
| 55 | A step is missing from the runbook entirely | Write it down now, in the report, while you still remember what you improvised |
| 70 | The check fails on `everything expected is listening` | Something was started and never enabled, and the reboot found it |

## Verification
`lab check s8-02-disaster-recovery --minutes <n>` — the full s8-01 suite, plus:

- **every** row count in the restored fingerprint against the live database,
  not just one;
- the elapsed time against `S8_RTO_MINUTES`, which fails if it was missed;
- the report naming what had to be improvised, and the loss window.

## Prevention
Three things come out of this drill that nothing else produces:

1. **A measured RTO.** Replace the guess in `lab.conf` with the number, and if
   you have to raise it, raise it deliberately and write down why.
2. **A measured RPO.** The loss window is the gap between the last archive and
   the deletion. If it is larger than you are comfortable with, the backup
   timer's interval is the dial.
3. **The improvisation list.** Every step you worked out rather than read is a
   gap in the runbook. Fix the runbook the same day — and then s8-03 finds out
   whether you fixed it well enough, with no internet and no help.

The structural fix, if anything here hurt: get the password file and the
`lab.conf` into the Git repository's orbit — encrypted, or at least recorded as
something that must exist elsewhere — because an encrypted archive and a lost
key is the most complete kind of data loss there is.

## What I did not know before this
That the two things most likely to be missing during a recovery are not data:
they are the key to the archive and the order of the steps. Both are free to
preserve and both are usually only on the machine that is gone.
