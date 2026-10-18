# s2-01 — author notes

**Why the log is generated rather than shipped.** Committing 5.7 MB of access
log to a repository that is otherwise text would be the largest file in it by
an order of magnitude, and it would carry 50,000 IP addresses through every
clone. Generating it costs two seconds and a seeded PRNG, and the addresses
never leave the RFC 5737 documentation ranges, which can never belong to
anybody. No run-time network call is involved; the rule holds.

**Why the PRNG is written out by hand.** Eight lines of linear congruential
generator rather than `random.seed()`, so the log is byte-identical on every
machine and every Python version. Grading does not need it — `check.sh`
computes the answers from whatever log is present — but an exercise where two
people can compare notes is worth eight lines.

**Why `break.sh` refuses to regenerate.** Idempotence here is not "produces the
same result twice"; it is "does not destroy work". Replacing the log under
someone who has answered three questions would invalidate their answers while
looking like a no-op. A second run says so and leaves it alone.

**Why the counts are planned rather than sampled.** "The top ten, most first"
has one correct ordering only if no two of the top eleven are tied. Sampling
from a weighted distribution gives ties often enough to matter, and a check
that marks a correct answer wrong is worse than no check. So the twelve heavy
addresses and paths get explicit, well-separated counts. The placement of the
404s shifts those counts a little afterwards, which is why `check.sh` verifies
the tenth and eleventh are not tied rather than trusting the plan — and reports
a tie as a fault in the generated log, with the fix, rather than as the reader's
error.

**Why the busiest address is not the 404 address.** Question 5 is the only one
of the six that is two steps, and the two steps can be done in either order
with different results. Filter then count is right; count then filter answers a
question nobody asked. If the answer to 5 were also the answer to 1, the wrong
pipeline would produce the right number and the lesson would be invisible. So
`203.0.113.99` owns 1,500 of the 3,600 404s and is eighth overall.

**Why the 5xx cluster.** Three quarters of them land in two adjacent hours.
Spread evenly, "5xx per hour" is a formatting exercise; clustered, it is the
first question anyone actually asks about a web server — *when did this start* —
and the answer looks like an incident rather than like noise.

**Why the check never prints the answer.** Every other check in this lab
explains itself as fully as it can, because the thing being learned is the
system. Here the thing being learned is the pipeline, and an answer printed on
failure turns attempt two into transcription. So the feedback is directional:
how many entries are wrong, which position first differs, whether a sum is high
or low. "Too low — is the whole file being read, and is it the right column?"
is the hint that teaches; the number is the hint that does not.

**The trap.** `| head -10`. Not in the reader's pipeline, where it is correct
and idiomatic — in `check.sh`, where it was written first and silently broke
everything. `head` exits after ten lines, `sort` upstream takes SIGPIPE, and
under `set -o pipefail` inside `$(...)` with `inherit_errexit` the command
substitution fails and errexit kills the check before a single assertion
prints. It needs enough input for `sort` to still be writing when `head` leaves,
which means it does not reproduce anywhere else in this repository and
reproduces every time here. The check now ends each pipeline in an `awk` that
reads to the end of its input, and says why in a comment.

That is the second errexit failure found in this build whose signature was
*silence* — the first was `health_check` aborting at "root is the only uid 0"
on every correct machine. Both were invisible for the same reason: a check that
dies before printing looks like a check that has not run yet.

**`PROVEN=real`.** Unusually for this lab it is honest here. This challenge
needs no systemd, no containers, no applications and no network: a log file and
`awk`. Generation and all seven grading paths — correct, correct-with-spaces,
right members in the wrong order, a short list, a sum too high, a sum too low,
the trap answer to question 5, and nothing answered at all — were run end to
end, and a container exercises every one of them exactly as the VM would.
