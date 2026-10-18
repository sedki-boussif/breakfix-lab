# s9-07 — The query that got slow

## Symptom
The ward filter on the placements page takes about half a second instead of
being instant. Nothing is broken. One user noticed, because she uses that filter
twenty times a day.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl -w '%{time_total}' .../api/placements/?ward=Ward%20Echo` vs the unfiltered endpoint | 480 ms vs 40 ms | Confirms it, and localises it to the filtered query rather than the page or the app |
| 2 | `EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM placements WHERE ward='Ward Echo' AND started_on > CURRENT_DATE - 200` | `Seq Scan on placements`, 14.7 ms, 60,000 rows read to return 1,779 | The plan is the answer |
| 3 | `SELECT indexname FROM pg_indexes WHERE tablename='placements'` | Only `placements_pkey` | Something that was there is gone |
| 4 | `git log`/migration history | The initial migration creates `ix_placements_ward_started` | Establishes what it should be, exactly, rather than inventing one |
| 5 | after recreating it, the same `EXPLAIN` | `Bitmap Index Scan`, 3.1 ms | A 4.7× improvement, and the plan changed, which is the real evidence |

**Dead end worth recording.** Looking at the application for an N+1 query or a
missing cache. Reasonable for "a page got slower", and `EXPLAIN` on the one slow
endpoint answers it faster than reading any code.

## Root cause
The index on `placements (ward, started_on)` had been dropped. The query fell
back to a sequential scan over 60,000 rows: still fast in absolute terms, four
to five times slower than it was.

## Fix
```bash
cd /opt/stages
docker compose exec -T db psql -U stages_owner -d stages \
  -c "CREATE INDEX ix_placements_ward_started ON placements (ward, started_on)" \
  -c "ANALYZE placements"
```

`ANALYZE` matters: the planner will not use a new index confidently until the
statistics know about it, and skipping it produces the confusing result where
the index exists and the plan has not changed.

**Both columns, in that order.** An index on `ward` alone improves the time and
leaves the `started_on` comparison to filter afterwards. The order follows the
query: equality first, range second.

## Verification
The plan uses a bitmap index scan and no longer contains `Seq Scan on
placements`; an index covering `(ward, started_on)` together exists; the filtered
endpoint answers in under half a second. Measured both ways: **3.1 ms with the
index against 14.7 ms without**, on the same data.

## Prevention
- **Indexes belong in migrations, not in a DBA's memory.** This one did — the
  initial migration creates it — which is the only reason its exact definition
  was recoverable.
- **Alert on query time, or sample `pg_stat_statements`.** A query that moves
  from 3 ms to 15 ms is invisible to every availability check and is the shape
  of trouble at ten times the data.
- **Take `EXPLAIN` seriously for "a bit slower".** The whole diagnosis was one
  command, and the reason it took a day to start is that half a second does not
  feel like an incident.
- **Know the table's growth curve.** At 60,000 rows this is 15 ms; at 600,000 it
  is a timeout. The fault was mild because the table is small, and the same
  missing index is an outage later.

## What I did not know before this
That `EXPLAIN (ANALYZE)` tells you both what the planner chose *and* how long it
actually took, so one command gives you the diagnosis and the measurement
together. And that recreating an index without `ANALYZE` can leave the plan
unchanged, which looks exactly like the fix not working.
