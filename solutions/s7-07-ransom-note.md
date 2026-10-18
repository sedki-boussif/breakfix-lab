# s7-07 — Files are encrypted and the server is asking for money

## Symptom
The placements application shows no uploaded documents. The uploads directory
contains files with random hex names and a `.locked` suffix, plus
`READ_ME_TO_RECOVER.txt` demanding 0.35 BTC within 72 hours and claiming the
backups have been removed. The applications are running and the database is
intact.

## Investigation

**Scope first.** Panic generalises; the first job is to establish what is
actually gone.

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl .../api/placements/count/` and `psql -c 'SELECT count(*)'` | 60,000 rows, unchanged | **The database is fine.** Halves the recovery before it starts, and is the single most valuable early finding |
| 2 | `ls -la "$(docker volume inspect -f '{{.Mountpoint}}' stages_uploads)"` | Hex names, `.locked`, plus the note | The damage is the uploads volume and nothing else |
| 3 | `file` and `xxd \| head` on a `.locked` file | High-entropy bytes, no recognisable header | Not renamed-only: the contents are destroyed. There is nothing to un-rename |
| 4 | `ls -la /var/backups/lab/` | `repo` is gone | The note's claim about backups is **partly** true |
| 5 | `sudo restic -r /srv/lab-offsite/repo snapshots` | Snapshots present and listed | And partly false. This is the moment s7-01 and s7-04 pay for themselves |
| 6 | `sudo restic -r … check --read-data-subset=5%` | Passes | The off-site copy is readable, not just listed — the lesson from s7-03 |
| 7 | `ps aux`, `sudo ss -ltnp`, `systemctl list-timers`, `ls /etc/cron.d` | Nothing unexpected | Nothing of the attacker's is still running. Established rather than assumed |

**Preserve before you repair.** Copying the scrambled files and the note costs
seconds and is the only record of what happened:

```bash
sudo mkdir -p /root/incident-2026-10-18
sudo cp -a "$UPLOADS"/*.locked "$UPLOADS/READ_ME_TO_RECOVER.txt" \
  /root/incident-2026-10-18/
sudo chattr +i /root/incident-2026-10-18/*   # so the next step cannot eat it
```

## Root cause
Within the drill: every file in the uploads volume overwritten with random bytes
and renamed, a ransom note written, and the local backup repository deleted. The
off-site copy was untouched, which is the only reason this is recoverable.

What the drill does **not** establish is how it got in — and on a real host that
is the question that matters most, because the recovery does not close it.

## Fix
```bash
PW=/etc/lab-backup/password
R=/srv/lab-offsite/repo
UPLOADS="$(docker volume inspect -f '{{.Mountpoint}}' stages_uploads)"

# 1. Stage the restore. Never straight over the damaged directory: you end up
#    with a mixture and no way to tell recovered from not.
sudo restic -r "$R" --password-file "$PW" restore latest \
  --target /tmp/recover --include "$UPLOADS"

# 2. Clear the damage, deliberately and completely.
sudo rm -f "$UPLOADS"/*.locked "$UPLOADS/READ_ME_TO_RECOVER.txt"

# 3. Put the files back with their ownership, which the app depends on (s3-05).
sudo cp -a /tmp/recover"$UPLOADS"/. "$UPLOADS"/
sudo chown -R 10001:10001 "$UPLOADS"

# 4. Prove the application can use them.
curl -fsS -F 'file=@/tmp/probe.png' http://127.0.0.1:8080/api/uploads/
```

**I did not pay, and I did not restart.** The note says not to restart, which is
the only line in it worth thinking about: a restart drops anything resident in
memory, which is both a reason to restart (stop it) and a reason not to
(evidence). Here, with nothing running and evidence already preserved, a restart
was unnecessary either way — so the decision was "not now, and for a stated
reason", which is what the report records.

## Verification
Real files back in the uploads volume, no `.locked` files anywhere, no note,
`stages` answering, an upload accepted and read back through the API, and the
placement count still 60,000 — the database was never the target and restoring
it too would have been unnecessary damage. Nothing unexpected listening.

## The loss window
Everything uploaded between the last off-site snapshot and the attack. For a
daily backup that is up to 24 hours of documents. Write the actual number down
and compare it with the RPO from s7-02: this is the cost of the backup schedule,
measured rather than assumed, and it is the argument for making it hourly if the
data deserves it.

## Prevention
- **s7-04 is the prevention.** An append-only off-site copy is the difference
  between this being a bad afternoon and being a negotiation. The local
  repository was deleted in seconds by something with root; the off-site copy
  survived only because it was out of reach.
- **Uploads are not a database.** They had no second copy anywhere except the
  backup, and a volume full of user documents deserves at least the same
  treatment as the tables.
- **Alert on mass file modification.** Thousands of files rewritten in a volume
  in minutes is a signature, and nothing watched for it.
- **Treat every credential this host held as compromised** and rotate it: the
  database passwords, the restic password, every key. The restore ends the
  outage; it does not end the incident.
- **Then rebuild.** You cannot establish the integrity of a machine from inside
  it; s8-02 is that exercise.

## What I did not know before this
How much of the first ten minutes is scoping rather than fixing — "the database
is intact" was available in one command and changed the whole shape of the
response. And that the ransom note is a useful document: everything it tells you
not to do is a decision someone wanted you not to make carefully.
