# s9-05 — Someone else changed something

## Symptom
The overnight report has not run. Yesterday's output is there, last night's is
not. The timer is enabled, nothing failed, and the site is fine.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl list-timers --all \| grep report` | Enabled, healthy, **next elapse two hours later than expected** | Not disabled, not failed. The "NEXT" column is the finding |
| 2 | `systemctl show -p OnCalendar -p NextElapseUSecRealtime <timer>` | `OnCalendar=*-*-* 02:17:00`, next elapse shifted | `OnCalendar` is interpreted in **local** time |
| 3 | `timedatectl` | `Time zone: Europe/Tunis (CET, +0100)` — and it was UTC | The change. Two hours, matching the shift exactly |
| 4 | `journalctl -u <timer unit> --since '3 days ago'` | Ran on schedule until the day of the change | Confirms the correlation with a date |
| 5 | scrolling back through the handover channel | "I fixed the server's timezone" the previous afternoon | The cause, in writing, a day before the symptom |

**Dead end worth recording.** Twenty minutes checking the job itself — running
it by hand (works), checking its `PATH` (fine, that was s5-09), checking
permissions. The job was never the problem. **Reading backwards through recent
changes should have been the second step, not the last.**

## Root cause
The system timezone was changed from UTC to Europe/Tunis. systemd interprets
`OnCalendar=` in local time, so every timer on the machine moved by the offset.
The job had not failed — it had not yet come due, and would have run two hours
later than anyone was watching for.

## Fix
A decision, not a revert. Machine schedules in UTC, human-facing output in
local time:

```bash
# Pin the schedule, so the timezone cannot move it again.
sudo systemctl edit lab-report.timer
# [Timer]
# OnCalendar=
# OnCalendar=*-*-* 02:17:00 UTC
sudo systemctl daemon-reload
systemctl list-timers --all | grep report      # next elapse now stable

# Keep the timezone change: it fixed a real complaint about the report's
# timestamps, and that was the right call.
```

For cron, the equivalent is `CRON_TZ=UTC` at the top of the file.

Why UTC for the schedule: local time moves twice a year at daylight saving, and
a job scheduled at 02:17 local runs twice on one night in October and not at all
on one night in March. That is a far nastier version of this same incident,
arriving months later with no change to blame.

## Verification
The report is fresh again, the schedule states its timezone explicitly, the
clock is still synchronised, and the applications are unaffected. And the report
names the timezone change as the cause — without that, the fix expires in March.

## Prevention
- **Read recent changes before investigating a symptom.** One day apart, same
  channel, and the first message contained the answer to the second.
- **Pin every machine schedule to UTC.** Timers, cron, backup windows,
  certificate renewals. Display in local time; schedule in UTC.
- **Alert on the absence of expected output**, not on job failure. This job
  never failed, so every failure-based alert was correct and silent — which is
  s5-09's lesson arriving by a different route.
- **Record timezone changes as changes.** It feels like a display setting and it
  is a scheduling change for the whole machine.

## What I did not know before this
That `OnCalendar=` is local-time by default and that appending `UTC` is all it
takes to pin it — and therefore that changing a server's timezone silently
reschedules every timer on it. Also that the "NEXT" column of `list-timers` is
where this class of fault is visible, and I had only ever read the "LAST" one.
