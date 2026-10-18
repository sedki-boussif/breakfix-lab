# s2-02 — Write sysinfo.sh

## The goal
Six facts about a machine, in a format something else can read, from a script
that runs without `sudo` and passes `shellcheck`.

## The script

```bash
#!/usr/bin/env bash
# sysinfo.sh — the six things worth knowing before you start guessing.
set -euo pipefail

printf 'hostname: %s\n' "$(hostname)"
printf 'uptime_seconds: %d\n' "$(awk '{printf "%d", $1}' /proc/uptime)"
printf 'load_1min: %s\n' "$(awk '{print $1}' /proc/loadavg)"

# "Used" here means MemTotal - MemAvailable: the memory that is not available
# to a new process. free's "used" column counts buffers and cache as used,
# which makes a healthy Linux machine look full.
total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
printf 'memory_used_mb: %d\n' "$(( (total_kb - avail_kb) / 1024 ))"

# -P for the portable format: without it a long device name wraps and NR==2
# reads half a row.
printf 'disk_used_pct: %d\n' \
  "$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5+0}')"

printf 'top_processes:\n'
ps -eo comm,rss --sort=-rss --no-headers |
  awk 'NR <= 5 {printf "  %d  %s  %d\n", NR, $1, $2/1024}'
```

## Where each number comes from, and what the alternative costs

| Field | Source | The version that breaks |
|---|---|---|
| uptime | `/proc/uptime`, field 1 | `uptime`'s prose, whose shape changes with duration; or `date +%s`, which is a timestamp and claims a 1970 boot |
| load | `/proc/loadavg`, field 1 | `uptime \| awk -F'load average:'`, which depends on the locale |
| memory | `MemTotal - MemAvailable` | `free`'s `used` column, which counts cache and makes a healthy box look full |
| disk | `df -P /`, field 5 | `df -h` with no argument, which measures whichever filesystem the cwd is on |
| processes | `ps -eo comm,rss --sort=-rss` | `ps aux \| sort -rn -k4`, which sorts by a percentage and breaks when a column shifts |

## Verification

```bash
sysinfo.sh                      # as yourself, no sudo
shellcheck sysinfo.sh           # before the check does it for you
sysinfo.sh | grep -c ':'        # the keys are parseable, which is the point
lab check s2-02-sysinfo-script
```

The check holds the output to being numeric where numbers were specified, to
being plausible, and to agreeing with `df` on the root filesystem — plus
`shellcheck` clean and the same keys on a second run.

## Prevention
This is the first half of a habit and s2-03 is the second: a script that prints
`key: value` is a script another script can consume. Worth adding when the need
appears — the kernel version, whether a reboot is pending
(`/var/run/reboot-required`), the inode percentage as well as the block
percentage, since `s5-02` is the incident where those two disagree.

Keep it in `/usr/local/bin` and in your runbook repository. s8-03 is the
exercise that finds out whether it was worth keeping.

## What I did not know before this
That `free`'s "used" and "the memory that is not available" are different
numbers, and that the second one is what `MemAvailable` exists to tell you —
the kernel's own estimate, rather than an arithmetic guess about how much cache
it would give back. And that `df` needs `-P` to guarantee one row per
filesystem.
