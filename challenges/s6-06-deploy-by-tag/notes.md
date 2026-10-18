# s6-06 — author notes

**Why this one is worth more than it looks.** It is the challenge closest to
something already real: the private application this lab stands in for deploys
by tag, so this is a rehearsal rather than an introduction. That changes what
the check should assert. The point is not that the reader learns what a tag is;
it is that the rollback gets *performed and observed* at least once somewhere
it does not matter, because the first time anyone performs a rollback is
otherwise during an incident, from a runbook nobody has executed.

**Why the observability assertion is the centre of it.** Every other property
here — a tag exists, HEAD is at it, the record matches — can be satisfied by a
deployment that does nothing. "Rolled back successfully" is a sentence people
say when a command exited 0, and the command exiting 0 is not evidence that the
behaviour changed. So the check deploys the other tag with the reader's own
script, requires the application's response to differ, deploys back, and
requires it to return. That is the whole challenge; the rest is preconditions.

**And why that assertion needs a control.** "The response changed" proves
nothing if the response changes anyway. A Django page carrying a CSRF token
differs on every request, and a check comparing raw bodies would pass on noise
— a green result that means nothing, which is the failure mode this repository
keeps finding. So two requests are compared *before* any deployment, and the
assertion is abandoned with an explanation if they already differ. The
fingerprint also normalises long token-shaped runs, which removes the common
case without hiding a real content change, and `S6_06_PROBE_URL` exists for
when that is not enough.

This is the same shape as `assert_absent`'s planted instance, arrived at from
the other direction: there, prove the detector can see something; here, prove
the detector is not already seeing something.

**Why `git pull` is asserted against rather than merely discouraged.** `pull`
deploys "whatever the branch is at now", which is a different artefact every
time it runs and has no name. You cannot roll back to it, cannot tell a
colleague what is live, and cannot say what changed when it breaks. The
assertion greps the script, and the report is checked too — if `git pull` is
mentioned there it must be in order to explain why not. `git fetch --tags` is
fine and deliberately not matched: the fetch was never the problem, the merge
was.

**Why the record lives outside the checkout.** `git describe` answers "what is
this working tree at", which stops being the deployment's history the moment
anyone runs a git command in that directory. The record answers "what did we
deploy, and when" — the question you actually have at 02:00 — and the check
requires it to *agree with reality*, because a drifted record is worse than no
record: it will be believed.

**Why the unknown-tag refusal is checked for side effects as well as exit
code.** A script that validates the tag after checking it out, or that reports
failure having already moved HEAD, leaves the machine in a state nobody chose.
The check captures HEAD, asks for a tag that does not exist, and requires both
a non-zero exit and an unmoved HEAD. Validation that happens after the
destructive step is not validation.

**The trap.** Creating a branch at the tag instead of detaching. Everything
works, `git describe` says the right thing, and the deployment is fixed in place
— until someone runs `git pull` on that branch and the "version" moves silently
underneath. The hints name it; the check catches the general case by requiring
HEAD to be exactly a tag's commit, which a branch tip stops being as soon as one
commit lands on top.

A second, quieter one: `rev-parse --verify <name>` without the `refs/tags/`
prefix also matches branch names, so a typo that happens to be a branch deploys
the branch and reports success.

**Why the restore is an EXIT trap.** The check deploys other versions of a real
application. Leaving the machine on the wrong one because an assertion
misbehaved would be worse than not checking at all, so the starting tag is
restored on every exit path — and the trap falls back to a plain `git checkout`
if the reader's own script is what failed.

**`PROVEN=mock-process`.** The application was a small HTTP server reading the
checked-out file, so the deploy genuinely changed what was served and the
observability assertion was exercised end to end against real git. Verified
against nine cases: a correct script (seventeen assertions), `git pull` in the
script, an unknown tag accepted, two tags with no visible difference, a
response that changes on its own, HEAD on an untagged branch tip, a dirty
working tree, a drifted deploy record, and no record at all. Not exercised: a
real Django deployment with migrations and `collectstatic`, which is why this is
mock rather than real.
