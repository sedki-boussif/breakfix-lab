# s7-02 — Restore drills

## The goal
Find out whether the backups restore, and how long it takes, before the day it
matters. Three drills: one file, one database, everything onto a machine that
has never seen it.

## What I did, and what each took

| Drill | How | Elapsed |
| --- | --- | --- |
| One file | `restic restore latest --target /tmp/drill-file --include <uploads path>` | record yours |
| One database | restore the dump, `createdb stages_drill`, `psql -f`, count rows | record yours |
| Everything, fresh machine | second VM: install restic, fetch the password, restore, bring up the stacks | record yours |

```bash
PW=/etc/lab-backup/password
R=/srv/lab-offsite/repo

# Drill 1 — a single file, never onto the live path.
time sudo restic -r "$R" --password-file "$PW" restore latest \
  --target /tmp/drill-file --include /var/lib/docker/volumes/stages_uploads/_data

# Drill 2 — a database, into a NEW database, compared against the fingerprint.
time ( sudo restic -r "$R" --password-file "$PW" restore latest \
         --target /tmp/drill-db --include /var/backups/lab/staging/stages.sql
       sudo -u postgres createdb stages_drill
       sudo -u postgres psql -q -d stages_drill \
         -f /tmp/drill-db/var/backups/lab/staging/stages.sql )

# The comparison that matters: against the fingerprint from the snapshot, not
# against the live database, which has moved on since the backup.
sudo restic -r "$R" --password-file "$PW" dump latest \
  /var/backups/lab/row-counts.txt
sudo -u postgres psql -tAq -d stages_drill -c 'SELECT count(*) FROM placements'
```

## What I got wrong first
Compared the restored count against the **live** database, which had moved on
since the snapshot, and spent twenty minutes convinced the restore was lossy. It
was correct; the comparison was not. The fingerprint exists for exactly this.

## Verification
The restored row count equals the fingerprint's `placements=` value for the
snapshot that was restored. The live database's count is unchanged from before
the drills — a drill that damages production is not a drill. The three elapsed
times are in the report, next to the recovery time objective I wrote down
beforehand.

## What the numbers actually said
Write both down: the RTO you assumed, and the time you measured. The gap is the
finding. Mine was wrong in the direction they always are — the transfer was
fast and *finding the right snapshot and remembering the password location* was
most of the wall clock, which is a procedure problem rather than a bandwidth
problem, and procedure problems are fixable for free.

## Prevention — what makes the next drill faster
- **A one-page runbook** with the repository paths, the password location, and
  the three commands. Most of the measured time was lookup.
- **Drill on a schedule**, quarterly, and record the time each quarter. A single
  measurement is an anecdote; four are a trend.
- **Keep the fingerprint inside the snapshot**, so it travels with the data. A
  fingerprint only on the live machine is gone exactly when needed.
- **Make the third drill real at least once.** Restoring onto the machine that
  made the backup proves the archive is readable and nothing else.

## What I did not know before this
How much of a restore is finding things rather than copying them — and
therefore that the thing to optimise is the runbook, not the pipe. Also that
`restic dump <snapshot> <path>` prints a single file from a snapshot to stdout
without restoring anything, which makes checking a fingerprint a one-liner.
