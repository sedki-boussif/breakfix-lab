# s5-09 — author notes

**What the fault really is.** The nightly job calls a helper that lives in
`/usr/local/bin`. That directory is on an interactive login's `PATH` and is
**not** on the `PATH` cron gives a job, which is `/usr/bin:/bin`. So the script
fails at the first call with `command not found`, exits non-zero, produces no
output, and the stale report from three weeks ago sits there looking plausible.

**Why nothing alerted.** Three reasons, all worth noticing. cron mails failure
output to the job's owner, and nothing on the box reads that mail. The job's own
output file still exists, so any check that tested for existence rather than
freshness was satisfied. And the job exits non-zero into nothing — cron records
that it ran, not that it worked.

**Why there is no reporter.** This is the only brief in the stage with no
symptom, no timestamp and no ticket: someone noticed a number had not changed. A
silent failure has no reporter by definition, which is what makes it the most
expensive kind — three weeks here, and the only reason it surfaced is that a
human remembered what the number should look like.

**The trap, and it is the one everyone falls into.** Running the job by hand. It
works perfectly, because your shell has `/usr/local/bin` on its `PATH`; the file
is refreshed, the numbers update, and the cause is untouched, so it fails again
that night. `check.sh` runs the job with the `PATH` its *schedule* provides — read from the
crontab, defaulting to cron's own `/usr/bin:/bin` — for exactly this reason: a
fix that depends on the environment of whoever is logged in is not a fix.

A bare `env -i` is **not** good enough, and the first draft used one. With no
`PATH` set, `sh` picks a default, and on Debian and Ubuntu that default includes
`/usr/local/bin` — so the assertion passed the broken job and proved nothing. It
was caught by watching it pass in a state where it should have failed. This is the
same shape as hand-starting gunicorn in s3-01 and killing the holder in s5-03 —
the lab's recurring theme is that a fix which depends on a human being present is
not one.

**Level 3.** The cause is hidden from the symptom: the symptom is a stale number,
the cause is an environment variable, and nothing in between announced itself.

**No absence assertion, and why.** "Nothing in the job chain depends on an
interactive PATH" is the same statement as "the job succeeds with the PATH its schedule provides", which is asserted
directly. Running the real job in cron's own environment is
itself the evidence — a positive claim needs no planted control. The first draft
did wrap it in `assert_absent` with a control script, which looked more rigorous
and was worse: the detector examined the control rather than the job, so the
assertion said nothing at all about the job while appearing to.

The lesson generalises, and is now in the specification: an absence claim needs a
control, a positive claim is its own evidence, and a control pointed at anything
other than the real subject proves only that the detector works.
