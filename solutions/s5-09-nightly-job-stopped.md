# s5-09 — The nightly job silently stopped

## Symptom
No symptom, and no ticket. Someone noticed in a meeting that a set of numbers
had not changed in about three weeks. The report file exists, the job is still in
the crontab, nothing failed visibly, no alert fired, and no error arrived
anywhere anyone reads.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `ls -l /var/lib/lab-jobs/report.csv` | mtime 23 days ago | The one hard fact. Gives a date to look for a cause around, and confirms the file exists — which is why every existence-based check was happy |
| 2 | `cat /etc/cron.d/lab-nightly-report` | `PATH=/usr/bin:/bin`, then the schedule | The job is still scheduled. Ruled out "someone removed it", and the `PATH=` line is already visible here if you know to look |
| 3 | `journalctl -u cron -S '25 days ago' \| grep nightly \| tail` | `CMD (… nightly-report.sh)` every night, including last night | Decisive: cron is running it every night. So it runs and fails, rather than not running |
| 4 | `sudo /opt/lab-jobs/nightly-report.sh && ls -l …report.csv` | Works perfectly, file refreshed | The trap, and a useful data point: it works in *my* environment |
| 5 | `sudo env -i PATH=/usr/bin:/bin /bin/sh -c /opt/lab-jobs/nightly-report.sh` | `labreport: not found` | Reproduces the real failure. The difference between 4 and 5 is the entire fault. Note the explicit `PATH`: a bare `env -i` lets `sh` pick a default that includes `/usr/local/bin` on Ubuntu, and the job then works, which would send you back to square one |
| 6 | `command -v labreport` | `/usr/local/bin/labreport` | Which is on an interactive `PATH` and not on cron's |

**Dead end worth recording.** Step 4 — running the job by hand and seeing it
work. It is the natural next move and it is actively misleading: it refreshes the
file, so the symptom disappears, and it proves only that your login shell differs
from cron's. Had I stopped there, the report would have been three weeks stale
again within a day, and the evidence (an old mtime) would have been destroyed.

## Root cause
The job calls `labreport` by name. It lives in `/usr/local/bin`, which is on an
interactive login's `PATH` and not in the `PATH=/usr/bin:/bin` the crontab sets.
The script failed at its first command every night, produced no output, and left
the previous report in place looking plausible.

## Fix
Either make the schedule carry the environment the job needs:

```bash
sudo sed -i 's|^PATH=.*|PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin|' \
  /etc/cron.d/lab-nightly-report
```

or — better — make the job not depend on an environment at all, by calling the
helper by absolute path inside the script. The second is preferable because it
survives being moved to a different scheduler, a container, or a systemd timer,
none of which will have your `PATH` either.

Then prove it the way cron will run it:

```bash
sudo env -i PATH=/usr/bin:/bin /bin/sh -c /opt/lab-jobs/nightly-report.sh
ls -l /var/lib/lab-jobs/report.csv
```

Why not just run it by hand nightly: because that is not a fix, it is a person.

## Verification
The report is fresh, and the job succeeds with the `PATH` its own schedule
provides — read from the crontab, defaulting to cron's `/usr/bin:/bin`. That is
the assertion a hand-run cannot satisfy, and it accepts either legitimate fix:
an explicit `PATH` in the schedule, or absolute paths inside the script.

## Prevention
- **Alert on freshness, never on existence.** A check that tested for the file
  would have passed every day for three weeks. `find … -mtime +1` and alert.
- **A dead man's switch for every scheduled job**: the job reports success
  somewhere, and the absence of that report is what alerts. This is s7-01's
  pattern and it is the only thing that catches a silent failure.
- **Read cron's mail, or stop generating it.** `MAILTO=` with somewhere real, or
  redirect output to a log that is monitored. Failure output going nowhere is why
  this was silent.
- **Test every scheduled job under `env -i PATH=/usr/bin:/bin`** once, when it is
  written — with the `PATH` spelled out, since a bare `env -i` is more generous
  than cron is. Most cron faults in the world are this one.
- **`set -euo pipefail` in job scripts** so a failing first command cannot be
  followed by something that writes a half-empty file — worse than writing
  nothing.

## What I did not know before this
That cron's `PATH` is `/usr/bin:/bin` and nothing else, so `/usr/local/bin` —
where almost everything hand-installed lives — is invisible to every cron job
unless you say otherwise. And that "it works when I run it" is evidence of a
difference between environments, not evidence that the job is fine.
