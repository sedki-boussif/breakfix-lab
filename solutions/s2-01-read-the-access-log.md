# s2-01 — Read the access log

## The goal
Six questions about a 50,000-line nginx access log, answered with pipes.

## The field numbers, first
Everything else follows from these. The combined format is:

```
192.0.2.17 - - [18/Oct/2026:14:22:07 +0000] "GET /api/theses/ HTTP/1.1" 200 4821 "-" "curl/8.5.0"
$1         $2$3 $4                    $5    $6   $7            $8        $9  $10
```

```bash
head -1 access.log | tr ' ' '\n' | cat -n     # when in doubt, count them
```

Address `$1`, path `$7`, status `$9`, bytes `$10`. Field `$4` keeps its leading
bracket, which is why the hour comes out by splitting rather than cutting.

## The six

```bash
L=$S2_01_DIR/access.log

# 1. Top ten addresses.
awk '{print $1}' "$L" | sort | uniq -c | sort -rn | head -10

# 2. Top ten paths. Same pipeline, different column — which is the point.
awk '{print $7}' "$L" | sort | uniq -c | sort -rn | head -10

# 3. Every status code with its count, ascending by code.
awk '{print $9}' "$L" | sort -n | uniq -c

# 4. 5xx per hour. The hour is the second field when $4 is split on colons.
awk '$9 >= 500 && $9 < 600 { split($4, a, ":"); print a[2] }' "$L" | sort | uniq -c

# 5. The address with the most 404s. Filter FIRST, then count.
awk '$9 == 404 {print $1}' "$L" | sort | uniq -c | sort -rn | head -1

# 6. Total bytes served.
awk '{s += $10} END {print s}' "$L"
```

To get them into the answer sheet's format without retyping:

```bash
# comma-separated, most first
awk '{print $1}' "$L" | sort | uniq -c | sort -rn | head -10 \
  | awk '{printf "%s%s", sep, $2; sep=","} END {print ""}'

# code:count pairs
awk '{print $9}' "$L" | sort -n | uniq -c \
  | awk '{printf "%s%s:%s", sep, $2, $1; sep=","} END {print ""}'
```

## What each one reveals

| # | What it answers | Why you would ask it |
|---|---|---|
| 1 | Who is hitting this server | A single address with 40% of the traffic is a crawler, a retry loop, or an attack |
| 2 | What they are hitting | Tells you which endpoint to look at when the server is slow |
| 3 | The health of the whole log in one view | A 404 count that dwarfs the 200s means something is linking wrongly |
| 4 | **When** it broke | The first question about any incident, and the one a flat count cannot answer |
| 5 | Who is scanning you | 404s concentrated on one address with paths like `/.env` is a scanner, not a user |
| 6 | What it cost | Bandwidth, and the input to a cache decision |

Question 5 is the one worth doing carefully. `sort | uniq -c | sort -rn` on the
whole file then grepping 404 answers a different question from filtering to the
404s and then counting, and in this log the two give different addresses — the
busiest address overall is eighth among the 404 generators.

## Prevention
Keep these. A file of six pipelines is the most useful thing in this stage, and
the second time you write them from scratch will not be faster than the first.
Worth adding to it as you go: requests per minute during an incident window,
the slowest paths if you log `$request_time`, and the user agents behind the
404s.

## What I did not know before this
That the timestamp field keeps its opening bracket, so `cut` on the field gives
you `[18/Oct/2026:14:22:07` and the hour has to come out of a `split` on
colons. And that `sort | uniq -c` needs the `sort` — `uniq` only collapses
*adjacent* duplicates, which is why the pipeline has two sorts in it and both
are doing different jobs.
