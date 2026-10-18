# s2-03 — Write appcheck.sh

## The goal
One command that answers "is everything up?", with timestamps, warnings, and an
exit code a timer can act on.

## The script

```bash
#!/usr/bin/env bash
# appcheck.sh — the three applications, the disk and the memory, in one pass.
set -euo pipefail

LAB_ROOT=/home/you/breakfix-lab
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

# From the environment, with defaults: a threshold you cannot change is a
# threshold you cannot test.
disk_max="${APPCHECK_DISK_PCT:-80}"
mem_min="${APPCHECK_MEM_MIN_MB:-256}"

rc=0
ts()  { date '+%Y-%m-%dT%H:%M:%S'; }
say() { printf '%s %-5s %s\n' "$(ts)" "$1" "$2"; }

for pair in "stages:${STAGES_URL}" "leaves:${LEAVES_URL}" "nurse:${NURSE_API}"; do
  name="${pair%%:*}"; url="${pair#*:}"
  # || true is load-bearing: without it, set -e ends the script here on the
  # first refusal and the other two are never checked.
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
  if [[ "$code" == 200 ]]; then
    say OK "$name $url $code"
  else
    say FAIL "$name $url ${code:-000} no answer"
    rc=1
  fi
done

pct="$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5+0}')"
if (( pct >= disk_max )); then
  say WARN "disk / at ${pct}% (threshold ${disk_max}%)"
else
  say OK "disk / at ${pct}% (threshold ${disk_max}%)"
fi

avail="$(awk '/^MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( avail < mem_min )); then
  say WARN "memory ${avail}MB available (floor ${mem_min}MB)"
else
  say OK "memory ${avail}MB available (floor ${mem_min}MB)"
fi

# FAIL exits non-zero; WARN does not. The caller is a timer that pages on a
# non-zero exit, and a disk at 81% is not worth waking anyone for.
exit "$rc"
```

## The four decisions in it

| Decision | Why | What the other choice costs |
|---|---|---|
| `\|\| true` on curl | so one refusal does not end the script | the other two applications are never checked, and the exit code is right by accident |
| `--max-time 5` | a half-open connection is not a refused one | the script hangs for two minutes per application on the day it matters |
| thresholds from the environment | so the warning path can be tested | a warning that has never fired, which is the same as no warning |
| `rc` accumulated, `exit "$rc"` at the end | the first problem is rarely the only one | a cascade reported as one failure |

`%{http_code}` is `000` when the connection never happened. Worth keeping
distinct from a 500 in the output: "nothing is listening" and "something
answered badly" send you to different places.

## Verification

```bash
appcheck.sh ; echo "exit=$?"                        # all up: 0
APPCHECK_DISK_PCT=0 appcheck.sh                     # must WARN on disk
APPCHECK_MEM_MIN_MB=999999 appcheck.sh              # must WARN on memory
sudo systemctl stop leaves.service
appcheck.sh ; echo "exit=$?"                        # non-zero, and names leaves
sudo systemctl start leaves.service
lab check s2-03-appcheck-script
```

The check does all of that itself, including stopping the application — and
confirms it really stopped before judging the output, because an assertion
about a failure that never happened proves nothing either way.

## Prevention
This is the script a timer should run. Once it exits non-zero reliably:

```ini
# /etc/systemd/system/appcheck.timer
[Timer]
OnCalendar=*:0/5
```

with a service whose `ExecStart` is the script. Then the exit code matters, and
the `WARN`-versus-`FAIL` decision stops being academic. `s5-09` is the incident
where a scheduled job stops working silently, and `s7-01`'s dead-man's-switch is
the pattern that catches it — both of which this script is the first half of.

## What I did not know before this
That `set -e` plus `curl -f` produces a script that *looks* like it handles
failure, because the exit code is non-zero for the wrong reason. It took
stopping an application and reading the output to see that the other two were
never checked at all — the exit code was right and the script was useless, which
is the most expensive kind of wrong.
