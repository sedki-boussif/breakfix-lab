# s9-07 — author notes

**What the fault really is.** The index on `placements (ward, started_on)` is
dropped. The query that filters on those columns falls back to a sequential scan
over 60,000 rows: still fast in absolute terms, about four to five times slower
than it was.

**Why this is a separate challenge from s9-02, measured differently.** Measured
on the development machine, the filtered count runs in **3.1 ms** on a bitmap
index scan and **14.7 ms** on a sequential scan. That ratio is unmistakable in
`EXPLAIN (ANALYZE)` and invisible through a load generator sharing two cores,
because 11 ms of wall clock disappears into the noise of the generator itself.
So this challenge is measured with the query planner and the query's own
execution time, and the load-shaped fault — a starved worker pool — kept the
load-shaped measurement in s9-02.

**Why the seed volume matters.** At a few hundred rows both plans are under a
millisecond and the fault does not exist. `SEED_PLACEMENTS` is 60,000 for this
reason, and `SETUP.md` section 9 explains the number rather than asserting it.

**Why level 3.** The cause is one object in a schema, and the symptom is a
rounding error in a page load. The difficulty is entirely in taking "a bit
slower" seriously enough to measure, and in knowing that `EXPLAIN` is where the
answer lives.

**The trap.** Making the symptom go away without the index: raising the
application's cache, adding a `LIMIT`, or denormalising. Each of them improves
the number and leaves the table unindexed, so the next query that filters on
those columns is slow too. `check.sh` asserts the **plan** — an index scan, not
a sequential scan — rather than only the time, so a fix that is fast for the
wrong reason fails.

The subtler trap: creating an index on `ward` alone. It helps, the time improves,
and the ordering half of the query still scans. The check requires both columns.

**`PROVEN=unproven` here, but the mechanism is measured.** The index behaviour,
the plan change and the timings were verified against real PostgreSQL 16 with the
real migration and the real 60,000-row seed while building the stand-in. What has
not been exercised is this challenge's own break, check and reset against a
running stack.
