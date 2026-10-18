# s9-06 — author notes

**The break is a genuine no-op.** Nothing is changed, nothing is planted, and
there is no fault to find. `break.sh` records that the round happened and
touches nothing else.

**Why this is a challenge and not a joke.** Every other exercise in this
catalogue rewards finding something, which trains exactly the wrong instinct: an
investigator who must produce a cause will produce one. Declaring a system
healthy, with evidence, on the third complaint from a frustrated user, is
genuinely harder than finding a fault — and it is the more common situation.

**Why the third complaint.** Social pressure is part of the exercise. The brief
is mildly accusatory, the previous two investigations found nothing, and the
temptation is to change something — restart a service, bump a worker count — so
that there is an action to report. That is the failure mode: a change with no
diagnosis, which makes the next investigation harder because the system is no
longer the one that was measured.

**What a passing answer looks like.** Not "I looked and it seemed fine" but a
set of measurements with numbers in them, a statement of what would have
indicated a fault, and an explicit conclusion. The user is owed the numbers more
than she is owed a culprit — and if the next report says the same thing, the
baseline from this one is what makes the comparison possible.

**And the honest residue.** "No fault found" is not "she is wrong". It means the
fault is not on this machine and not in this measurement window. The report
should say what was *not* ruled out: her network, her device, a path between, or
something intermittent on a cycle longer than the window. That list is the
difference between a dismissal and a finding.

**No trap, and the check is unusual.** There is nothing to fix, so there is no
wrong fix. The check asserts health via `health_check` — the same definition
`lab chaos --check` uses — and asserts that the report concludes no fault found
with evidence. It is the only check in the lab that reads the report as the
deliverable rather than as a record.

**`PROVEN=real`.** There is nothing to exercise but the health assertions and
the report assertions, both of which are real.
