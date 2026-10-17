# s5-04 — The API keeps dying at random

## Symptom
Intermittent 502s from the theses API through the afternoon — roughly one request
in ten, at 13:52, 14:06, 14:21, 14:40, 15:12 — with the service healthy whenever
anyone looks. Reported as a database connection-pool problem, with a request to
increase the pool size. The reporter also mentions in passing that the box feels
sluggish, "probably the indexer".

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `docker inspect -f '{{.RestartCount}} {{.State.StartedAt}}' <api>` | RestartCount 18, started four minutes ago | The decisive observation: the process is not failing to reconnect, it is *being replaced*. Ruled out the entire connection-pool theory and the requested fix |
| 2 | `docker compose logs api --tail 50` | Clean startup logs, no tracebacks, no shutdown messages | Ruled out an application crash. It is not exiting; it is being killed |
| 3 | `sudo dmesg -T \| grep -iE 'oom\|killed'` | `Memory cgroup out of memory: Killed process … (gunicorn)` repeatedly | Names the mechanism. Note **cgroup** out of memory, not a global OOM |
| 4 | `free -h` | ~2.4 GB available on the host | Ruled out machine-wide memory pressure, and so ruled out the indexer as the cause. A cgroup limit is unaffected by free memory elsewhere |
| 5 | the OOM line's cgroup path | The api service's own cgroup | Confirms the limit that was hit belongs to the API itself, which is also why no other service is affected |
| 6 | `docker inspect -f '{{.HostConfig.Memory}}' <api>` | 50331648 — 48 MB | The fault |
| 7 | `ps -eo pid,comm,rss,etimes --sort=-rss \| head` | `indexer-warmup`, 256 MB resident, running since this morning | The sluggishness, and a genuine second issue — but not the cause of the kills |

**Dead end worth recording.** Killing the hog first, because it is the obvious
culprit and the reporter pointed at it. The box gets faster, `free` looks better,
and the API keeps dying on exactly the same schedule — which is the observation
that proves a cgroup limit is involved rather than host memory pressure.

## Root cause
The api service had `mem_limit: 48m` — a memory limit on its own cgroup far below
what it needs. Every time it grew past 48 MB the cgroup OOM killer killed it, the
restart policy brought it back, and it served requests until it grew again. The
memory hog made the host slow and had nothing to do with the kills.

## Fix
Remove or raise the limit in the compose file, then recreate the service, and
deal with the hog separately:

```bash
# in compose.yaml, remove mem_limit or set it to a real figure:
#     mem_limit: 512m
cd /opt/nurse && docker compose up -d --force-recreate api
sudo pkill -f indexer-warmup      # the separate, real, lesser problem
```

Why a sane limit rather than none: a limit is good practice — it stops one
service taking the machine down — but it has to be above the service's actual
working set. 48 MB for a Django API with a database connection pool is below the
floor at which it can even start serving.

Why not bump the connection pool, as asked: more pooled connections means more
memory, so it would have made the kills more frequent. Acting on a confidently
reported cause would have made the incident worse.

## Verification
The hog is gone, the limit is above the floor, and — the part that matters — the
API's restart counter does not move for three minutes while the kernel log stays
free of new OOM kills. Both absence claims prove their own detectors first: the
hog detector against a process planted under the same name, and the OOM detector
against a kill planted deliberately in a throwaway 8 MB cgroup.

## Prevention
- **Alert on the restart counter, not just on liveness.** Every health check
  passed all afternoon, because the service was healthy between kills. A service
  that restarts eighteen times in three hours is in an outage regardless of what
  a probe says at any instant.
- **Set memory limits from measurement.** Run the service, watch its working
  set, add headroom. A number typed from memory into a compose file is how this
  happens.
- **Read the OOM line properly.** "Memory cgroup out of memory" and a global OOM
  are different incidents with different fixes; the cgroup path in the message
  tells you whose limit was hit.
- **Distrust a reported cause, especially a plausible one.** "Connection pool"
  fitted the fifteen-minute pattern well enough to have cost an afternoon.

## What I did not know before this
That a cgroup OOM kill is completely invisible in `free` — the host can have
gigabytes available while a service is being killed for exceeding 48 MB — and
that the kernel log distinguishes the two cases explicitly. Also that a restart
counter is the fastest way to tell "failing to reconnect" from "being killed",
and it is one command.
