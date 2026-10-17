# s5-01 — Disk is full

## Symptom
`/srv/lab-scratch/uploads` is at 100% and the application cannot write to it.
A colleague had already deleted application logs and emptied caches without
freeing anything, and reported that `du` accounts for almost none of the usage —
concluding that `df` must be wrong.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `df -h /srv/lab-scratch/uploads` | 100% used, a few MB free | Confirms which filesystem. Not the root volume, so nothing system-wide |
| 2 | `df -i /srv/lab-scratch/uploads` | 1% of inodes used | Ruled out inode exhaustion, which presents with the same `ENOSPC` — see s5-02 |
| 3 | `du -sh /srv/lab-scratch/uploads/*` | About 4 MB, as reported | Reproduces the colleague's result, which is the thing to explain rather than to trust |
| 4 | `du -xh --max-depth=2 /srv/lab-scratch/uploads` | ~490 MB, under `.cache` | The gap closes immediately. `du PATH/*` relies on a shell glob, and a glob does not match dotfiles — so the first command was blind to a dot-directory, not wrong about the files it did see |
| 5 | `sudo find /srv/lab-scratch/uploads -xdev -type f -size +64M -exec ls -lh {} +` | One 487 MB file, `.cache/.import-spool/.spool-20261016.dat`, mtime 16 Oct 03:14 | The answer, and the only remaining evidence of when it appeared |
| 6 | `sudo lsof /srv/lab-scratch/uploads/.cache/.import-spool/.spool-20261016.dat` | Nothing holding it | Ruled out s5-03's shape: deleting it will actually return the space |

**Dead end worth recording.** Checking for a deleted-but-held file with
`lsof +L1` before running the `find`. It costs ten seconds and eliminates the
other common cause of a `df`/`du` disagreement, so it is worth doing in either
order.

## Root cause
A single 487 MB pre-allocated file in a dot-directory on the uploads
filesystem. The usual `du PATH/*` could not see it because the shell glob skips
dotfiles, which is why the usage appeared unaccountable.

## Fix
```bash
sudo rm /srv/lab-scratch/uploads/.cache/.import-spool/.spool-20261016.dat
df -h /srv/lab-scratch/uploads
```

Record the owner and mtime before deleting: they are the only trace of what
wrote it, and the logs that would have said more were already deleted.

Why this rather than a workaround: freeing the same number of bytes by deleting
logs, caches or old backups brings the percentage down and leaves the file in
place to fill the volume again, while destroying the evidence of its origin. The
check looks for the file, not the percentage, for that reason.

## Verification
`df -h` shows the filesystem under 80%, `find -size +64M` returns nothing on it,
and all three applications still answer. The check proves its own search first by
planting a sparse 128 MB file, requiring the detector to find it, and removing
it — otherwise a `find` with a wrong predicate would report "clean" for ever.

## Prevention
- **Alert on the filesystem, per mount, at 80%** rather than discovering it at
  100%. A full volume is an outage; an 80% volume is a ticket.
- **`du -xh --max-depth=2 PATH`, never `du -sh PATH/*`.** The second form is the
  one that lies, and it is the one everybody types.
- **Find out what wrote it.** A dot-directory called `.import-spool` with a
  dated filename is a spool that is not being cleaned up, which means a job that
  fails without removing its temporary file. That is the real fix.
- **Do not delete logs to free space during an incident.** They are the evidence,
  and they are almost never where the space went.

## What I did not know before this
`du -sh /path/*` and `du -sh /path` can differ by hundreds of megabytes, and the
reason is the shell, not `du`: the glob never matches a dot-directory. Nearly
every "df and du disagree" mystery is either that or a deleted file still held
open, and both are ten seconds to check.
