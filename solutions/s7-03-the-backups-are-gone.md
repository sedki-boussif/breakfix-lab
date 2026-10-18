# s7-03 — The backups are gone

## Symptom
The placements tables are empty. The local backup repository directory is gone.
The off-site repository's newest snapshot is corrupted, and a colleague has
already run `restic check` (which reported errors) and `restic repair` (effect
unknown) before handing it over.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `psql -c '\dt'` then `SELECT count(*)` per table | Tables present, zero rows | Not a dropped database and not a broken connection: something emptied the data. Scope established before anything is restored |
| 2 | `ls -la /var/backups/lab/` | The `repo` directory is absent | Confirms the local copy is gone rather than unreadable |
| 3 | `sudo restic -r /srv/lab-offsite/repo snapshots` | Several snapshots, newest first | **The 3-2-1 rule paying for itself.** The off-site copy exists and is listed |
| 4 | `sudo restic -r … check` | Pack file errors, naming one pack | The damage is specific, not repository-wide |
| 5 | `sudo restic -r … check --read-data-subset=5%` | Which snapshots are actually *retrievable* | The important distinction: `snapshots` lists what the index claims; this tests what can be read |
| 6 | `sudo restic -r … restore <second-newest> --target /tmp/recover` | Succeeds | The newest good snapshot, found by testing rather than assuming |
| 7 | `restic dump <that snapshot> /var/backups/lab/row-counts.txt` | The fingerprint *belonging to that snapshot* | What to compare the restore against |

**Dead end worth recording.** Trying `restore latest` first. It fails on the
corrupt pack, which costs a few minutes and teaches the lesson directly: a
listed snapshot is not a readable one.

**The thing that was already done to it.** `restic repair` had been run. Worth
establishing early, because it changes what the repository is now — and it is
why the first question to a reporter mid-incident is "what have you already
tried", not "what happened".

## Root cause
Two faults: every local archive deleted, and the newest off-site snapshot's pack
file truncated. The data loss is bounded by the gap between the corrupt snapshot
and the newest readable one.

## Fix
```bash
PW=/etc/lab-backup/password
R=/srv/lab-offsite/repo
SNAP=<the newest snapshot that passes --read-data-subset>

# Stage it. Never restore straight over the only remaining state.
sudo restic -r "$R" --password-file "$PW" restore "$SNAP" --target /tmp/recover

# Check it before trusting it.
sudo restic -r "$R" --password-file "$PW" dump "$SNAP" /var/backups/lab/row-counts.txt

# Then load it.
( cd /opt/stages && docker compose exec -T db \
    psql -U stages_owner -d stages ) < /tmp/recover/var/backups/lab/staging/stages.sql

# And deal with the damage rather than around it.
sudo restic -r "$R" --password-file "$PW" check --read-data-subset=5%
# forget the corrupt snapshot, prune, and re-run a backup so there is a good
# newest one again
```

Staging first is not caution for its own sake: if the candidate snapshot turns
out to be the damaged one, restoring directly would have destroyed the empty-
but-consistent database that was the only remaining state.

## Verification
The data is back and the count matches the fingerprint **for the snapshot that
was restored**. `restic check --read-data-subset=5%` passes. The applications
answer. And the report states the loss window achieved.

## The finding: the loss window
This is the deliverable, not the restore. The snapshot restored was from
`<timestamp>`; the data was lost at `<timestamp>`; the window is the difference.
Compare it with the RPO written down in s7-02. If the window is larger than the
objective — and it usually is, because the objective was set by assuming the
*newest* snapshot would always be usable — then the objective was wrong, and the
fix is either more frequent snapshots or a verification step that would have
caught the corruption before it mattered.

## Prevention
- **`restic check --read-data-subset` on a timer**, weekly. A repository is only
  verified if something reads the data back; an index that lists a snapshot
  proves nothing.
- **More than one off-site copy**, or an older one kept longer. "3-2-1" means
  three copies; two was nearly not enough here.
- **Find out what emptied the database.** The restore ends the outage; it does
  not end the incident.
- **Alert on the age of the newest *readable* snapshot**, not on the backup job
  exiting zero.

## What I did not know before this
That `restic snapshots` and `restic check --read-data-subset` answer different
questions, and that only the second one is evidence. Also that "restore the
latest backup" is a habit worth unlearning: the correct instinct is "restore the
newest backup I have verified", and on a bad day those are not the same snapshot.
