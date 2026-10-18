**The goal.** Write `appcheck.sh` — the script that answers "is everything up?"
in one command, and that a timer could run every five minutes without anyone
reading its output unless something is wrong.

Put it at `$S2_BIN_DIR/appcheck.sh` and make it executable.

**What it does:**

1. **Requests each of the three applications** at the URLs in `lab.conf` —
   `STAGES_URL`, `LEAVES_URL`, `NURSE_API` — and reports whether each answered.
2. **Warns when the root filesystem is over 80% full**, or when available
   memory is under a floor.
3. **Timestamps every line**, so its output means something when it is found in
   a log two days later.
4. **Exits non-zero if anything failed**, and zero when everything is fine.

**The output format.** Every line starts with an ISO-8601-ish timestamp, then a
level, then the detail:

```
2026-10-18T14:22:07 OK    stages http://127.0.0.1:8080/ 200
2026-10-18T14:22:07 OK    leaves http://127.0.0.1:8081/etoile-formation-conge/ 200
2026-10-18T14:22:08 FAIL  nurse http://127.0.0.1:8000/api/health/ 000 connection refused
2026-10-18T14:22:08 WARN  disk / at 87% (threshold 80%)
2026-10-18T14:22:08 OK    memory 1840MB available (floor 256MB)
```

Levels are exactly `OK`, `WARN` and `FAIL`. A failing application is `FAIL` and
**its line must name the application** — `leaves`, not just the URL — because
the first thing anyone does with this output is search it for the name of the
thing they were told is broken.

**The thresholds come from the environment**, with sensible defaults:

| Variable | Default | Meaning |
| --- | --- | --- |
| `APPCHECK_DISK_PCT` | `80` | warn at or above this root usage |
| `APPCHECK_MEM_MIN_MB` | `256` | warn below this much available memory |

This is not decoration. A threshold you cannot change is a threshold you cannot
test, and the check sets both to values that force a warning in order to prove
the warning path works at all. A monitoring script whose alarm has never fired
is a monitoring script that has never been tested.

**What exits non-zero.** A `FAIL` must. Whether a `WARN` does is your call —
both are defensible, and the two answers suit different callers — but
**decide it deliberately and say which in the report**, because the caller is
a timer that will act on the exit code and not on the prose.

**The standard this will be checked against:**

- With all three applications up, it exits **0** and prints an `OK` line naming
  each of them.
- Every line begins with a timestamp, and the timestamps are from **now**.
- With one application stopped, it exits **non-zero**, and the `FAIL` line
  **names that application**. The check stops one and starts it again
  afterwards, whatever the result.
- With `APPCHECK_DISK_PCT=0` it emits a disk `WARN`; with
  `APPCHECK_MEM_MIN_MB` set above the machine's memory it emits a memory
  `WARN`. Neither is allowed to crash the script.
- It is `shellcheck` clean, `#!/usr/bin/env bash`, `set -euo pipefail`.

**One trap worth naming in advance.** `set -e` and a failing `curl` do not
coexist by accident: a bare `curl` that gets a connection refused will end your
script at line 4 with no output and exit 1, which looks like a working failure
path and is not — it never checks the other two applications. Capture the
status instead of letting it propagate.
