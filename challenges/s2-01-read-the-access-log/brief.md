**The goal.** Answer six questions about a 50,000-line nginx access log, using
the shell. No Python, no spreadsheet, no editor — `awk`, `sort`, `uniq`, `cut`,
`grep` and pipes. The questions are not hard; the point is the pipeline, and
the reason it is worth building once deliberately is that at 03:00 you will
need it and will not want to be inventing it.

The log is at `$S2_01_DIR/access.log` and the answer sheet is next to it at
`answers.txt`. It is the combined format, which is what nginx writes by
default:

```
192.0.2.17 - - [18/Oct/2026:14:22:07 +0000] "GET /api/theses/ HTTP/1.1" 200 4821 "-" "curl/8.5.0"
```

**The six questions**, also in the answer sheet:

1. **The ten addresses with the most requests**, most first.
2. **The ten paths with the most requests**, most first.
3. **The count of every status code** in the log.
4. **The 5xx responses per hour**, for every hour that has at least one.
5. **The single address responsible for the most 404s.** Note that this is a
   different question from number 1, and has a different answer.
6. **The total bytes served** — the sum of the response size column.

**The formats, exactly.** Getting the format wrong is graded as a wrong answer,
which is also true of a report:

| Key | Format | Example |
| --- | --- | --- |
| `top_ips` | ten addresses, comma separated, most first | `192.0.2.1,198.51.100.2,...` |
| `top_urls` | ten paths, comma separated, most first | `/,/api/theses/,...` |
| `status_counts` | `code:count` pairs, ascending by code | `200:41000,301:1900,404:3600` |
| `fivexx_by_hour` | `HH:count` pairs, ascending by hour | `09:3,14:675,15:671` |
| `top_404_ip` | one address | `203.0.113.1` |
| `bytes_total` | one whole number | `216452013` |

Spaces after the commas are fine. Hours are two digits, as they appear in the
log.

**What the check will and will not tell you.** It computes all six answers from
the log itself and compares. When an answer is wrong it says *how* — how many
entries are off, which position first differs, whether a number is too high or
too low — and never says what the right answer is. Transcribing a number you
were given teaches nothing; being told your sum is too low and working out that
you were reading the wrong column is the entire exercise.

Everything in the log is invented. Every address is from the RFC 5737
documentation ranges, which can never belong to anybody.
