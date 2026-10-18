Her observation is the diagnosis: fine for one person, unusable for many. That is a concurrency limit, not a slow query — a slow query is slow for one person too.
Measure it instead of trying it. The lab has a load generator: `. lib/load.sh` then `lab_load_run <url> 1 10` for one at a time, and `lab_load_run <url> 20 20` for twenty. Compare p50 and p95 between the two.
At concurrency 1 the latency is fine and at concurrency 20 the p95 is seconds. Requests are queuing, which means something upstream of the work is limited: workers, connections, or a pool.
Count the things that serve requests. `systemctl cat nurse-api` for the gunicorn worker count, `ps -ef | grep gunicorn` for how many are actually running, and `SHOW max_connections` plus `SELECT count(*) FROM pg_stat_activity` on the database.
Raise the limit that is actually binding — and only that one. Workers cost memory, connections cost memory on the database side; changing both at once means you learn nothing about which mattered.
Re-measure at the same concurrency afterwards and put both numbers in the report. "It feels better" is how you end up doing this again next month.
