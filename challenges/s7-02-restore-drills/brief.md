**The goal.** Find out whether your backups restore, and how long it takes —
before the day you need to know.

Three drills, in order, each timed:

1. **One file.** Restore a single file from the uploads volume to a scratch
   location, without touching the live copy.
2. **One database.** Restore the `stages` database into a throwaway database
   and compare its row counts against the fingerprint taken at backup time.
3. **Everything, onto a machine that has never seen it.** A second VM, or a
   rebuilt one. If you have no second VM, restore into a container or a new
   directory tree and say so in the report — and be honest in it about what that
   does not prove.

**The standard this will be checked against:**

- The restored row counts **match the fingerprint** from the snapshot you
  restored, not the current live database. A restore that returns the wrong data
  silently is worse than one that fails.
- Each drill's **elapsed time is recorded** in the report, in a form you can
  compare with next quarter's.
- The live data is **untouched** — a drill that damages production is not a
  drill.

**Write down your recovery time objective before you start**, then compare it
with what you measured. The number you discover is almost never the number you
assumed, and that gap is the whole point of the exercise.
