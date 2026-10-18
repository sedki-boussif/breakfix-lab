**The goal.** Backups that would actually get the lab back, rather than backups
that exist.

Three applications, two databases, one uploads volume. Build the thing that
copies them somewhere they survive this machine, on a schedule, encrypted, with
retention that does not grow for ever — and an alert when it stops.

**The standard this will be checked against:**

1. An archive exists **off this VM** — on `/srv/lab-offsite`, which is a
   separate filesystem, so a full local disk does not take the backups with it.
   (Off-VM is simulated locally throughout this lab. The pattern is what you are
   learning, not the vendor.)
2. The repository is **encrypted**: the files in it are not readable without the
   password, and the password is not in the repository.
3. **Retention is honoured**: old snapshots are pruned, and the number kept
   matches what you configured.
4. It runs **on a timer**, not from your shell history.
5. A **success marker** is written after each successful run, and something
   **alerts when that marker goes stale** — kill the timer and an alert must
   appear. A backup system with no dead-man's-switch tells you nothing on the
   day it stops.
6. A **fingerprint** is taken at backup time — row counts per table — so a
   restore can be checked against what was actually backed up rather than
   against hope.

The lab's `lab.conf` names every path involved. Read it first; nothing here
needs you to invent a location.

**The dead-man's-switch is local.** A real one pings a third-party service that
alerts when the ping stops. Here, something on this machine checks the marker's
age and appends to `BACKUP_ALERT_LOG`. The mechanism is the lesson; the vendor is
not, and this lab makes no network calls.
