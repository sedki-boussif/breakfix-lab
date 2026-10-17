# s5-03 — Disk full, and nothing big to delete

## Symptom
`/srv/lab-scratch/logs` is at 98%, writes to it fail, and `du` accounts for
about 4 MB of it. The previous engineer eliminated hidden directories, large
files and quotas, found a 400 MB discrepancy he could not explain, and concluded
the filesystem was corrupt and needed `fsck` — asking explicitly that the log
writer not be restarted, so the process state survives for a post-mortem.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `df -h` then `du -xh --max-depth=3` | 98% used, 4 MB accounted for | Reproduces the gap. ~400 MB unaccounted |
| 2 | `df -i` | 2% of inodes used | Ruled out s5-02's shape |
| 3 | `sudo find /srv/lab-scratch/logs -xdev -size +10M` | Nothing, including dotfiles | Ruled out s5-01's shape. The space is not reachable by any path, which is the real clue |
| 4 | `sudo lsof -nP +L1` | One process, `leaves-logwriter`, holding a file with link count 0 of ~400 MB on that filesystem | The answer. `+L1` means "link count less than 1" — files that have been deleted and are still open |
| 5 | `sudo ls -l /proc/<pid>/fd` | `9 -> /srv/lab-scratch/logs/leaves/access.log.1 (deleted)` | Names the file, the descriptor and the pid — everything the fix needs |
| 6 | `sudo fsck -N /dev/loop0` | Would require unmounting | Worth checking only to confirm the previous engineer's plan was both unnecessary and expensive |

**Dead end worth recording.** The `fsck` theory. It is not a stupid conclusion
from the evidence that had been gathered — `df` and `du` disagreeing with no
explanation does look like metadata damage — and the thing that eliminates it is
one command, `lsof +L1`, that had not been run.

## Root cause
A process holds an open file descriptor on a 400 MB log file that has already
been unlinked. The directory entry is gone, so nothing that walks the filesystem
can see it, but the blocks are not released until the last descriptor closes.
`df` counts blocks; `du` walks paths.

## Fix
```bash
sudo truncate -s 0 /proc/<pid>/fd/9
df -h /srv/lab-scratch/logs
```

Writing nothing through the descriptor releases the blocks immediately, while the
process keeps running and keeps its state. No unmount, no `fsck`, no restart, no
downtime.

Why not kill or restart the writer: it works, and it is what almost everyone
does. It also throws away the process — which in a real incident is the evidence
you are being asked to preserve, and is often a service you cannot restart during
business hours. The technique above is the one worth owning precisely because it
does not require either.

## Verification
`df -h` shows the filesystem under 80%, no deleted file on it is still holding space — the descriptor is
still open, which is the point, but it now refers to a zero-length file — and
the holding process is still running with its original pid. The check proves its own
detector first by creating a file, opening it from a background process,
unlinking it, requiring the detector to spot it, and killing only its own planted
holder.

## Prevention
- **Log rotation must signal the writer.** `copytruncate`, or a `postrotate` that
  reloads the service. This fault is what rotation without either produces, every
  time.
- **Alert on `df` rather than on `du`.** A monitoring check built on directory
  sizes would have reported this filesystem as nearly empty while it was full.
- **Put `lsof +L1` in the runbook for any full-disk report**, right beside
  `df -i`. Between them they explain nearly every unaccountable filesystem.
- **Do not reach for `fsck` on a mounted filesystem with a plausible explanation
  outstanding.** It is disruptive, it requires downtime, and here it would have
  found nothing wrong.

## What I did not know before this
That you can reclaim the space without touching the process, by truncating
through `/proc/<pid>/fd/<n>`. The descriptor is a path to the inode, so writing
nothing to it frees the blocks while the process holds its handle — which turns a
"restart it in the maintenance window" problem into a one-second fix.
