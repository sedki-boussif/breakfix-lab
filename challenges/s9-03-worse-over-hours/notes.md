# s9-03 — author notes

**What the fault really is.** A process appending to a log file at a few
megabytes a minute. Nothing is broken; the filesystem fills over hours, and the
machine becomes slow and then unhappy. A reboot stops the writer, which is
exactly why the reboot "fixes" it and why the symptom is weekly rather than
constant.

**Why it is level 4.** The cause is hidden from the symptom by *time*. Every
instrument reads normally at any single moment early in the cycle, and the
reporter has been looking at precisely the wrong moment for a week. The
investigative move — take two readings and subtract — is simple and is not what
anyone reaches for first.

**Why the baseline from SETUP matters.** `SETUP.md` section 9 asks for a
recorded size of the log and the audit table at deployment time, and `SEED_AUDIT`
is 5,000 rather than zero, because **a rate needs something to subtract**.
Starting from an empty table makes any growth look infinite and nothing look
like a trend.

**The trap.** Truncating the file. The space comes back, the machine is fine,
and the writer is still writing — so the same hours recur, and the next person
sees a file that is small and concludes it is not the problem. `check.sh`
measures the **growth rate over a window** rather than the current size, so a
truncate without stopping the writer fails: the file is small and still growing.

A second, legitimate-looking shortcut: adding a logrotate rule. That is
containment, and it is the right thing to do *as well* — but it bounds the
symptom rather than fixing the cause, and the report has to say which one was
done.

**The positive control.** "Nothing is growing" is an absence claim, so the
detector is proved first: the check plants a writer appending at a known rate,
requires the rate detector to see it, stops it, and only then asserts that
nothing is growing. A rate detector that silently measured zero — a path that
does not exist, a unit mix-up, a window too short — would otherwise pass for
ever.

**`PROVEN=real`.** File growth, two-point rate measurement, and the planted
control are all exercised for real.
