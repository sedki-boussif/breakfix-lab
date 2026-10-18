# s9-03 — It gets worse over hours

## Symptom
The machine is fine in the morning and slow by late afternoon. A reboot fixes
it. Nobody has found anything wrong, because the looking has always happened
shortly after a reboot.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | — | "A reboot fixes it and it returns over hours" | Accumulation. Ruled out configuration, which does not change between reboots, and pointed at a resource |
| 2 | `df -Pk /srv/lab-scratch/growth; sleep 300; df -Pk ...` | Used kB climbed by ~10 MB in five minutes | **The method:** the same reading twice, subtracted. A single reading at any moment looks normal |
| 3 | `sudo find /srv/lab-scratch/growth -type f -printf '%T@ %s %p\n' \| sort -rn \| head` | One file, recently modified, large and growing | Found by *rate* and recency, not by size — a big static file is not the problem |
| 4 | `sudo lsof /srv/lab-scratch/growth/leaves/debug.log` | A process named `leaves-debug-writer` holding it | The writer |
| 5 | `ls -l /proc/<pid>/exe`, `tr '\0' ' ' < /proc/<pid>/cmdline` | bash, in a loop, appending every 50 ms | What it really is, as opposed to what it is called |
| 6 | `df -Pi` and `free -m`, same two-reading method | Flat | Rules out the other two accumulations — inodes and memory — so the finding is specific |

**Dead end worth recording.** `du -xsh` on the usual directories at a single
moment. Everything looked plausible, because at that moment it was. The
two-reading method is the entire difference between an hour of looking and five
minutes.

## Root cause
A process appending to a debug log at roughly 2 MB/minute — about 120 MB an
hour, which fills the volume over a working day. The reboot stopped the writer,
which is why the reboot "fixed" it.

## Fix
```bash
# Stop the writer — the cause.
sudo pkill -f leaves-debug-writer

# Then reclaim, and confirm the rate is flat.
sudo truncate -s 0 /srv/lab-scratch/growth/leaves/debug.log
A=$(df -Pk /srv/lab-scratch/growth | awk 'NR==2{print $3}'); sleep 60
B=$(df -Pk /srv/lab-scratch/growth | awk 'NR==2{print $3}'); echo "$(( B - A )) kB/min"
```

Truncating without stopping the writer buys exactly the same number of hours
again, and leaves a small file that the next person will dismiss. The order
matters: writer first, space second.

**Containment as well as cure.** A logrotate rule with `size 50M` and
`rotate 3`, plus `copytruncate` or a reload, bounds any future recurrence. That
is worth adding *and* is not a fix — the report has to say which was done. I did
both and said so.

## Verification
The measured growth rate over a two-minute window is flat, the filesystem has
room, and the detector was proved against a writer planted on purpose — so a
rate of zero means zero rather than a broken measurement.

## Prevention
- **Alert on rate, not level.** A disk-usage alert at 80% fires hours into the
  problem; a "growing faster than X per hour" alert fires at the start.
- **Keep the deployment-time baseline** that `SETUP.md` asks for. A rate needs
  something to subtract, and a baseline recorded while things were fine is the
  cheapest possible measurement.
- **Treat "a reboot fixes it" as a diagnosis**, not as a workaround. It narrows
  the cause to something that accumulates in a running system, which is a small
  list: disk, inodes, memory, descriptors, processes, table rows.
- **Nothing should log at debug level in production unattended**, and anything
  that can should be bounded by the logging configuration rather than by hope.

## What I did not know before this
That two readings and a subtraction is a complete diagnostic technique, and that
I had never used it — every instinct is to look harder at one moment rather than
to look twice. Also that the Friday reboot was the most informative fact in the
report and had been left out of it as an embarrassment.
