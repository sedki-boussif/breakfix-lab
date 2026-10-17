# s5-05 — Everything is slow

## Symptom
All three applications are slow to respond since the start of the day. Nothing
fails, nothing errors, everything answers eventually. No timestamps, no error
text, and the reporter has eliminated her own internet connection but nothing
else.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl -w '%{time_total}\n' -o /dev/null -s <each app>` | 2.8 s, 3.1 s, 2.6 s | Turns "slow" into a number, so "fixed" can mean something later. Also ruled out one app being at fault: all three are equally slow, so it is the machine |
| 2 | `uptime` | load average 7.9, 7.4, 5.2 | — |
| 3 | `nproc` | 2 | The ratio is what matters: a load average of 7.9 on two cores means work is queued four deep. Ruled out the network, DNS and the applications |
| 4 | `free -h` and `df -h` | Plenty of both | Ruled out swapping and a full disk, the other two causes of machine-wide slowness |
| 5 | `ps -eo pid,user,comm,pcpu,etimes --sort=-pcpu \| head` | Four processes named `apt-cache-gen`, ~100% CPU each, running for 4 hours | Found them. `etimes` matches the start of the working day, which matches the report |
| 6 | `ls -l /proc/<pid>/exe` and `tr '\0' ' ' < /proc/<pid>/cmdline` | `/usr/bin/bash`, running `while :; do :; done` | The name was decoration. It is a shell busy loop, not anything to do with apt |
| 7 | `ps -o ppid= -p <pid>` and `sudo ls -l /proc/<pid>/cwd` | Parent gone, cwd a user's home | As much origin as remains. Worth recording before killing them |

**Dead end worth recording.** Checking the applications first — restarting
gunicorn, looking at the database. Reasonable, since the report is about the
apps, and it wastes ten minutes. The load-average-to-core-count ratio should be
the second thing anyone looks at on "everything is slow", after confirming it
really is everything.

## Root cause
Four shell busy loops, one more than the core count, running since the morning
under a name chosen to look like routine package maintenance. Every request
queued behind them.

## Fix
```bash
ps -eo pid,comm,etimes --sort=-pcpu | head      # record what they were first
sudo pkill -f apt-cache-gen
sleep 60 && uptime                              # a decaying average needs a minute
```

Record the pids, parents and working directories before killing them: they are
the only evidence of where they came from, and a process that was started once
will be started again.

Why kill rather than renice: `renice 19` makes the applications respond quickly
again, because they win the scheduler contest — and the cores stay pinned, the
load average stays at 8, power and heat stay up, and the next thing that wants
CPU still queues. It treats the measurement the user complained about and leaves
the cause running, which is why the check measures load average *and* response
time.

## Verification
Response time for each application back under a second, load average back below
the core count — allowing a minute or two, since it is a decaying average — and
no process consuming more than 80% of a core. The check's detector samples
`utime + stime` from `/proc/<pid>/stat` over two seconds rather than matching the
process name, and proves itself first against a busy loop planted on purpose.

## Prevention
- **Alert on load average relative to core count**, not on an absolute number. A
  load of 8 is fine on 16 cores and an outage on 2.
- **Alert on response time from outside**, which is what the user experiences.
  Every liveness check passed throughout this incident.
- **Never trust `comm`.** `/proc/<pid>/exe` and `/proc/<pid>/cmdline` are the
  facts; the name in `ps` is whatever the process chose to call itself.
- **Find out who started them.** Four loops under a disguised name on a server
  is either someone's loop left running or something worse, and the answer
  changes whether this is an incident or a security incident.

## What I did not know before this
How cheap it is to make a process lie about its name — `exec -a` is all it takes
— and therefore how little weight a plausible-looking name in `ps` deserves. Also
that load average is a decaying average, so a correct fix looks like it has not
worked for the first minute, and the fix for that is patience rather than more
changes.
