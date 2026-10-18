# s7-04 — Backups an attacker cannot delete

## The goal
Make the off-site copy something this machine can write to and cannot destroy —
because the credentials that write backups are the credentials ransomware uses
to delete them.

## What I built

The destination is owned by an identity this machine's backup job is not:

```bash
# A user that owns the destination and does nothing else.
sudo useradd --system --shell /usr/sbin/nologin backupkeep
sudo chown -R backupkeep:backupkeep /srv/lab-offsite/repo

# Append-only at the filesystem level, on the data that already exists.
sudo chattr -R +a /srv/lab-offsite/repo/data
sudo lsattr -d /srv/lab-offsite/repo/data
```

`chattr +a` is the honest local equivalent of object lock: a file can be opened
for *append* and not for truncate, rename or unlink, **and root cannot override
it without first removing the attribute** — which is itself a detectable action
rather than a silent one.

## What broke, and what that taught me
`chattr +a` on the whole repository broke `restic`: it rewrites its index and
its `snapshots` directory on every run, and append-only forbids the rewrite. So
the attribute belongs on `data/` — the pack files, which are genuinely
write-once — and not on `index/`, `snapshots/` or `keys/`.

That split *is* the design: find out which operations the tool actually needs,
then protect only what is immutable by nature. The requirements fight each
other and resolving the fight is the mission.

## Where retention lives now
It cannot live here any more, because pruning is deletion and this machine can
no longer delete. Two honest options:

1. **The destination prunes.** A job owned by `backupkeep` (or, in the real
   world, a lifecycle policy on the bucket) runs `restic forget --prune`
   against the repository it owns. The backup host never has that right.
2. **Nothing prunes, and the destination is sized for the retention.** Viable
   for a small lab and nothing else.

I chose (1). **If that job stops, the repository grows until the filesystem
fills**, and a full backup destination fails backups silently — which is
s7-05's failure mode arriving by a different route. So the destination's prune
job needs its own dead-man's-switch, exactly like the backup does.

## Verification
As root, on this machine: `rm` an existing pack file — refused. `truncate -s 0`
on it — refused. `rm -rf` the data directory — refused, and the directory is
still there. The file is byte-identical afterwards, so it was not quietly
overwritten instead. And a new `restic backup` still succeeds, which is the half
that makes it a solution rather than a different outage.

## What this does and does not prove
It proves the *shape*: the writer is not the deleter. It does not prove the
mechanism, because `chattr` is a single-machine trick and a real deployment uses
S3 object lock, a restic REST server in `--append-only` mode, or a separate SSH
identity with a forced command. All three implement the same sentence, which is
the thing worth carrying: **an identity that can write backups must not be able
to destroy them.**

## What I did not know before this
That `chattr +a` beats root — root must clear the attribute first, which is a
separate, auditable step — and that this is why it is a credible local stand-in
for object lock. Also that restic's directories have genuinely different
mutability requirements, so "make the backups immutable" is not one decision but
four.
