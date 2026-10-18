# s9-02 — author notes

**What the fault really is.** The API's worker count is reduced to one, via a
systemd drop-in that overrides `ExecStart`'s `--workers`. One worker serves one
request at a time; everything else queues. At concurrency 1 the latency is
normal, which is why every manual test passes.

**Why this and not the missing index.** The original specification offered
"a low worker limit **or** a missing index" as alternatives. They are not
interchangeable: at 60,000 rows the index is worth about 11 ms, which disappears
into the noise of a load generator sharing two cores, while a starved worker pool
produces a p95 of seconds because requests *queue* rather than merely running
slower. So the load-shaped fault keeps the load-shaped measurement, and the index
became s9-07 with a measurement that suits it — `EXPLAIN (ANALYZE)`.

**Why level 4.** The symptom only exists in a state the investigator is not in.
Every tool they reach for — curl, a browser, an SSH session — tests concurrency
1, and at concurrency 1 there is nothing wrong. Getting from "works for me" to a
measurement is the whole challenge.

**The trap.** Raising everything. Workers, `max_connections`, nginx's
`worker_connections`, and a pool size, all at once — the symptom clears and
nobody has learned which limit was binding, so the next capacity question starts
from zero again. The check asserts the p95 at a stated concurrency and requires
the report to carry **both** measurements, before and after, so the change has a
number attached to it.

The subtler trap: raising the worker count beyond what memory allows, which
trades a latency problem for s5-04's OOM problem. The report should say what the
new number costs.

**`PROVEN=unproven`.** It needs a real gunicorn with a real worker pool and a
real database under real load. A single-threaded stand-in would reproduce the
symptom and prove nothing about the fix.
