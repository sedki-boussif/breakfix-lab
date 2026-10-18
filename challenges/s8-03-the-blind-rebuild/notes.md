# s8-03 — author notes

**What is actually under test.** Not the person and not the machine: the
documentation. s8-01 proves a server can be built; s8-02 proves it can be
recovered; s8-03 asks whether it can be built by someone with nothing but the
files the builder left behind — which, three months later, is who the builder
is. Everything else in the catalogue tests a system. This tests the writing.

**Why the conditions are unenforceable, and why that is fine.** A script
cannot tell whether a person opened a search engine, and one that tried —
blocking DNS, auditing the browser — would be building a cheat detector instead
of a drill. So the check does not try. It asserts the one thing that leaves
durable evidence: the runbooks changed. Everything else is on the person's
honour, and the brief says so in those words, because the only person the
honesty serves is the one doing it. A runbook that passed because its author
looked something up is a runbook that fails at 02:00 when they cannot.

**Why the baseline is a Git commit, printed on the old machine.** The additions
happen *during* the rebuild, so a baseline recorded at arming time — after the
rebuild — measures nothing. It has to be taken before, on a machine that is
about to be replaced, which means it cannot be stored on that machine either.
Hence a seven-character sha the person writes down, passed back in with
`--since`. The lab state copy is kept as a fallback and is expected to be gone.

**Why `break.sh` refuses on a dirty runbook tree.** If there are uncommitted
changes at the baseline, then "what I added during the rebuild" and "what I had
not got round to committing" are the same diff, and the exercise measures
nothing while appearing to measure something. That is the same failure shape as
an absence assertion with no control: a green result that means nothing. The
refusal is cheap and the confusion is not.

**Why uncommitted work fails the final check too.** It is the most common way
the diff comes out empty, and the cause is almost never that nothing was
missing. The gap was written down in a file that was never committed, or in a
terminal scrollback that is about to close, and so it does not survive the next
machine — which is precisely the failure the challenge exists to prevent.
Catching it is worth one assertion.

**Why "nothing to add" still requires a commit.** The brief asks for a line
recording that the runbook was exercised blind on a date and found complete. An
untested runbook and a runbook tested once and found complete look identical on
disk, and the difference is most of what makes one trustworthy. Requiring the
commit also closes the loophole where "I needed nothing" is indistinguishable
from "I skipped the step".

**The trap.** Writing the runbook up afterwards, from memory, in one sitting at
the end. It feels more efficient and it produces a worse document every time,
because what survives an hour of being stuck is the *feeling* of having been
stuck, not the flag, the path or the ordering that resolved it. The brief says
fix-then-continue, in that order, and the commit count is what makes the
difference visible: one commit at the end is a summary, six commits during are
a record.

**Why there is no time gate.** s8-02 holds someone to an RTO because a recovery
has a clock in the real world. A blind rebuild does not: taking twice as long
while finding nine gaps is a better outcome than finishing quickly and finding
none, and a timer would push in exactly the wrong direction. The report still
records the time, because the comparison against s8-01's number is interesting
— it just is not a pass condition.

**A note on the hints.** The first one says that taking hints here is not free,
because the hints are documentation and reading them is the thing being
abstained from. It fires before any content is revealed, which is the right
place for that warning, and it costs a hint slot on purpose.

**`PROVEN=unproven`.** A bare image, a real reboot, and a human honouring an
unenforceable condition. What was verified off the VM: the baseline refusal on a
dirty tree, the commit and added-line counting against a scratch repository
with and without commits, the behaviour on a baseline sha that does not exist,
and the argument parsing.
