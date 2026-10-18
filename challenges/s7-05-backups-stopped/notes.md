# s7-05 — author notes

**What the faults really are.** Two, and the second is the one that matters:

1. The backup timer is disabled and stopped. No backups for three weeks.
2. The success marker has been **backdated to look recent**, so the
   dead-man's-switch sees a fresh marker and stays quiet.

Fault 1 alone is an inconvenience discovered within a day. Fault 2 is what turns
it into three weeks, and it is the realistic part: a marker that anything can
touch is a marker that lies. In the wild this is a `touch` in a wrapper script
that runs before the backup rather than after it, or an `|| true` that makes a
failed run look successful.

**Why the reporter found it by accident.** Silent failures have no reporter —
that is their definition. Someone wanted a file from ten days ago, and the
backups did not have it. Nothing was actually lost, which is what makes it a
near miss rather than an incident, and near misses are the cheapest lessons
available.

**The trap.** Enabling the timer and stopping there. Backups resume, the newest
snapshot becomes today, and the monitoring is still blind — so the next time the
timer stops, it is another three weeks. `check.sh` therefore requires the
dead-man's-switch to **actually fire**: it stops the timer, backdates the
marker, and demands a new line in the alert log. A fix that restores backups
without restoring the ability to notice fails.

The subtler trap: making the alert fire by writing to the log by hand. The check
compares line counts before and after a state it induces, so a line that was
already there does not count.

**What the report has to say.** Not "the timer was off" but why three weeks
passed without anyone knowing. The answer is that the only thing watching was
watching a value that could be forged, and the fix is monitoring that observes
the *outcome* — the newest snapshot's age in the repository — rather than a
marker that something claims to have written.

**`PROVEN=mock-systemd`.** The timer and marker half is exercised against a
stand-in service manager. The restic half needs a real repository.
