# s9-06 — Nothing is wrong

## Symptom as reported
"The site is really slow again", for the third time this week, from the same
person, with an explicit request to look properly rather than saying it is fine.

## Finding
**No fault found on the server.** Measured, not assumed. Details below, and the
list of what this does *not* rule out at the end — because that list is the
difference between a finding and a dismissal.

## What I measured

| What | Command | Result | Threshold that would have concerned me |
| --- | --- | --- | --- |
| Response time, each app, repeated | `curl -w '%{time_total}'` ×20 | p50 8 ms, p95 14 ms | anything over 1 s |
| Response time under concurrency | `lab_load_run <url> 20 20` | p95 120 ms, 0 errors | p95 over 1 s, or any errors |
| Load average vs cores | `uptime`, `nproc` | 0.31 on 2 cores | over 2.0 per core |
| Memory | `free -m` | 2.1 GB available | under 256 MB |
| Disk / inodes | `df -P /`, `df -Pi /` | 34% / 3% | over 80% either |
| Service restarts | `systemctl show -p NRestarts` ×4 | unchanged over 10 min | any movement |
| Unexpected listeners | `ss -ltnp` vs `EXPECTED_PORTS` | none | any |
| Growth rate | two `df` readings, 5 min apart | flat | over 64 kB/min |
| The lab itself | `lab doctor` | clean | any failure |

Everything is inside its threshold, by a wide margin, and the same measurements
taken an hour apart agree.

## Why I did not change anything
Three previous investigations found nothing, and the pressure at that point is
to *do* something — restart a service, raise a worker count — so that there is an
action to report. That would have been the actual mistake: a change with no
diagnosis, after which the system is no longer the one that was measured, and
the next investigation starts from a worse position than this one.

## What this does not rule out
- **Her network, device or browser.** Not measured here, and the most likely
  explanation for a symptom that is real for one person and invisible from the
  server.
- **The path between her and the VM.** A traceroute from her machine, and the
  same test from a second location, would separate these.
- **Something intermittent on a longer cycle than my window.** s9-03 was exactly
  that shape, and the measurements here span an hour, not a week.
- **Something that only affects a page I did not test.** I tested the endpoints
  she named and the health endpoints, not every page.

## What I did instead of a change
- Gave her the numbers, including what "fast" means in milliseconds, so the next
  report can be compared rather than argued about.
- Asked for three specifics next time: the time, the page, and whether it was
  slow for anyone next to her. Those three turn an unfalsifiable report into a
  measurable one.
- Set up a response-time check from outside the VM, recorded continuously, so
  the fourth report has a graph attached to it rather than a disagreement.

## Prevention — of the *situation*, not of a fault
The real failure here is that a user reported a problem three times and the
answer each time was an unevidenced "it's fine". A continuously recorded
external response-time measurement would have settled it the first time, in
either direction. That is the action item, and it is worth more than any fix
this investigation could have invented.

## What I did not know before this
How strong the pull is to find *something* once a third complaint arrives, and
that "no fault found, here are the numbers, here is what I did not rule out" is
a harder and more useful deliverable than a culprit. Also that the useful
response to an unfalsifiable report is to make the next one falsifiable.
