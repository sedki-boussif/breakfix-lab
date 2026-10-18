This is a measurement problem before it is a diagnosis. Time the request itself — `curl -w '%{time_total}'` against the filtered endpoint and against an unfiltered one — so "slower than it was" becomes two numbers you can compare.
The slow one filters by ward. Ask the database what it is doing with that query rather than guessing: `EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM placements WHERE ward = 'Ward Echo' AND started_on > CURRENT_DATE - 200;`
The plan says `Seq Scan`, and it is reading all sixty thousand rows to return a couple of thousand. A sequential scan on a table this size is milliseconds, which is exactly why the symptom is "a moment" rather than an outage.
`\d placements` in psql, or `SELECT indexname FROM pg_indexes WHERE tablename='placements';` — compare what is there against what the query needs. Something that was there is not.
Recreate the index on the columns the query filters by, in that order, then `ANALYZE` the table so the planner knows about it. Compare the plan before and after.
Record both execution times in the report. The ratio is the interesting number, and it is the only thing that will justify the index to anyone who asks why it exists.
