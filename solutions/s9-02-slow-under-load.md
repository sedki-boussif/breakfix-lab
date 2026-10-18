# s9-02 — Slow, but only under load

## Symptom
The theses site times out for students after a newsletter went out. It is
instant for the coordinator every time she tries it, and she is the only person
using it when she tries.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `. lib/load.sh; lab_load_run <url> 1 10` | p50 ~8 ms, p95 ~12 ms, no errors | Confirms her experience exactly. At concurrency 1 there is nothing wrong, which is why every manual test passed |
| 2 | `lab_load_run <url> 20 20` | p50 ~900 ms, **p95 ~4 s**, some timeouts | The fault, made visible. Ruled out a slow query — a slow query is slow at concurrency 1 too |
| 3 | `systemctl cat nurse-api` incl. drop-ins | `--workers 1` in a `91-lab.conf` override | Found it |
| 4 | `ps -ef \| grep -c '[g]unicorn'` | One worker process | Confirms what is running rather than what is configured |
| 5 | `psql -c 'SHOW max_connections'` and `SELECT count(*) FROM pg_stat_activity` | 100 allowed, 4 in use | Rules out the database as the binding limit, which matters: changing both at once teaches nothing |

**Dead end worth recording.** Looking at the database first. It is the usual
suspect for "slow under load" and it was nowhere near its limits —
`pg_stat_activity` answered that in one query.

## Root cause
The API was running with a single gunicorn worker. One worker serves one request
at a time; everything else queues, so latency grows with concurrency while
single-request latency stays perfect.

## Fix
```bash
sudo rm /etc/systemd/system/nurse-api.service.d/91-lab.conf
sudo systemctl daemon-reload && sudo systemctl restart nurse-api
ps -ef | grep -c '[g]unicorn'
. lib/load.sh && lab_load_run http://127.0.0.1:8000/api/health/ 20 20
```

One limit at a time, and measure after each. I changed only the worker count:
the database had 96 free connections, so raising `max_connections` as well would
have consumed memory for no benefit and left me unable to say which change
mattered.

**What the new number costs.** Each gunicorn worker is a full Python process —
roughly 80–120 MB here — so three workers is a few hundred megabytes of
resident memory that the 4 GB VM has to find. That is the trade, and it is the
same resource s5-04 is about: too many workers converts a latency problem into
an OOM problem.

## Verification
p95 at concurrency 20 under the stated threshold, error rate near zero, and both
measurements — before and after, at the same concurrency — in the report.

## Prevention
- **Load-test before announcing anything.** The newsletter was the load test,
  and the students were the testers.
- **Monitor p95 from outside, not availability.** Every uptime check passed
  throughout: they are all concurrency 1.
- **Alert on queue depth or request latency**, not on the service being up.
- **Record the capacity number.** "Three workers handles N concurrent users at
  p95 under X" is a sentence that makes the next capacity question arithmetic
  instead of an argument.

## What I did not know before this
That "it works for me" is a *measurement* — of concurrency 1 — rather than an
absence of evidence. And how completely a worker-pool limit hides from every
tool a person reaches for interactively, because every one of them is a single
request.
