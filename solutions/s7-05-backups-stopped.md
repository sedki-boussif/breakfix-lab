# s7-05 — Backups stopped three weeks ago

## Symptom
The newest backup snapshot is three weeks old. Nothing alerted, the alert log is
empty, and no mail arrived. Found by accident, by someone who wanted a file from
ten days ago.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl list-timers --all \| grep backup` | The backup timer is **inactive**, last run 25th | Answers the first question in one line: it is not failing, it is not running. Ruled out restic, the repository, the password and the destination |
| 2 | `systemctl status lab-backup.timer` | `disabled; inactive` | Someone or something disabled it |
| 3 | `journalctl -u lab-backup.service -S '30 days ago'` | Nothing since the 25th | Confirms: no attempts, therefore no failures, therefore nothing to alert on |
| 4 | `ls -l /var/backups/lab/last-success` | mtime **two hours ago** | The second fault, and the reason for the silence. A fresh marker on a machine that has not backed up in three weeks |
| 5 | `systemctl list-timers \| grep watch` | The watch timer is running fine | The monitoring was working perfectly. It was watching a value that lies |
| 6 | `restic -r … snapshots \| tail -3` | Newest snapshot the 25th | Corroborates the marker is wrong rather than the repository being stale |

**Dead end worth recording.** Checking the repository and the password first —
the instinct is "the backup is failing", and ten minutes went into proving the
destination was fine before `list-timers` was consulted. `systemctl
list-timers --all` should be the first command for any "the scheduled thing
stopped" report; it answers running-versus-failing immediately.

## Root cause
Two faults. The timer was disabled, so no backups ran. And the success marker
was backdated to look recent, so the dead-man's-switch — which was working —
saw a fresh marker and stayed quiet. The second fault is what turned a one-day
problem into a three-week one.

## Fix
```bash
sudo systemctl enable --now lab-backup.timer
sudo systemctl start lab-backup.service        # don't wait until tomorrow
sudo systemctl list-timers --all | grep backup
```

And the half that matters — make the monitoring observe the outcome rather than
a claim about it:

```bash
# Instead of trusting a marker any process can touch, ask the repository.
NEWEST=$(restic -r /srv/lab-offsite/repo --password-file /etc/lab-backup/password \
           snapshots --json | python3 -c \
  'import json,sys,datetime; s=json.load(sys.stdin); print(max(x["time"] for x in s))')
# then alert on the age of NEWEST
```

The marker stays — it is cheap and it is a useful first signal — but it is no
longer the *only* signal, because a marker is an assertion and the snapshot list
is evidence.

## Verification
The timer is enabled and active. The marker is fresh and corresponds to a real
run. And the dead-man's-switch actually fires: stop the timer, backdate the
marker, and a new line appears in the alert log — tested rather than assumed,
because this is the exact mechanism that failed.

## The gap, which is what the report is for
Three weeks with no backup and no alert. The thing that should have caught it on
day one was the dead-man's-switch, and it did not, because it compared against a
value that could be forged. The deeper answer: **monitoring that reads a
process's own claim about itself is not monitoring.** Anything that checks a
marker, a status file, or an exit code written by the thing being checked has the
same hole.

## Prevention
- **Alert on the age of the newest snapshot in the repository**, which is
  evidence, not on a marker, which is a claim.
- **Alert on timers being disabled**, separately. `systemctl list-timers --all`
  in the weekly check would have caught this on day one.
- **Write the marker last and only on success** — and never from a wrapper that
  cannot tell whether the backup worked.
- **Treat a near miss as an incident.** Nothing was lost, which is the only
  reason this was cheap, and the only lesson available for free.

## What I did not know before this
That `systemctl list-timers --all` shows disabled timers too — without `--all`
the thing you are looking for is the thing that is hidden. And the general
shape: a monitoring check is only as trustworthy as the independence of what it
reads, which rules out most of what people monitor.
