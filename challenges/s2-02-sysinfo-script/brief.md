**The goal.** Write `sysinfo.sh` — the script you run first when someone says a
machine is behaving oddly. Six facts, one screen, no arguments.

Put it at `$S2_BIN_DIR/sysinfo.sh` and make it executable.

**What it reports:**

| Key | What it is |
| --- | --- |
| `hostname` | this machine's name |
| `uptime_seconds` | how long since it booted, in seconds |
| `load_1min` | the one-minute load average |
| `memory_used_mb` | memory in use, in whole megabytes |
| `disk_used_pct` | how full the root filesystem is, as a number |
| `top_processes` | the five processes using the most memory |

**The output format**, because the check reads it and because a script whose
output can be parsed is worth more than one that cannot:

```
hostname: lab-vm
uptime_seconds: 184523
load_1min: 0.42
memory_used_mb: 1876
disk_used_pct: 37
top_processes:
  1  postgres  412
  2  gunicorn  268
  3  node      201
  4  nginx      94
  5  python3    61
```

One `key: value` per line for the five scalars. Then `top_processes:` on its own
line, followed by exactly five indented lines of `rank  name  megabytes`. The
numbers are plain: `37`, not `37%`; `1876`, not `1.8G`. A number with a unit
glued to it is a string, and the next thing you write will want to compare it.

**The standard this will be checked against:**

- It runs as an ordinary user, **without `sudo`**, and exits 0.
- All five scalar keys are present, and each value is **numeric** where a
  number is specified — which is most of the point of the format.
- The values are **plausible**: uptime is positive and not from 1970, the disk
  percentage is between 0 and 100, memory used is more than zero and less than
  the machine has.
- `top_processes` has **exactly five** entries, each with a name and a number,
  in **descending** order.
- It is **`shellcheck` clean**, with `#!/usr/bin/env bash` and
  `set -euo pipefail`. The same standard this repository holds itself to.
- Running it twice in a row gives the same keys both times.

**Two things worth getting right rather than working.** `uptime_seconds` from
`/proc/uptime` is a number; parsed out of `uptime`'s prose it is a brittle
regex that breaks the first time the machine has been up less than a day.
And "memory used" has more than one defensible definition — the one you want is
almost certainly not `free`'s `used` column, and `/proc/meminfo` has what you
need to compute it. Say which you chose in the report.
