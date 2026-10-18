# s9-01 — author notes

**What the fault really is.** The nurse vhost is rewritten to proxy to an
`upstream` block with three members, one of which points at a port where
nothing is listening. nginx round-robins, so roughly one request in three fails
with a 502 and the rest succeed.

**Why `proxy_next_upstream off` is part of the break.** By default nginx retries
the next member when one refuses the connection, so a dead member is invisible
to clients — measured while building this: thirty requests through a
three-member upstream with one dead member returned thirty 200s. The break
therefore also turns the retry off, which is a configuration real deployments
choose to avoid replaying non-idempotent requests. It is worth knowing in both
directions: the default hides this fault, and turning it off is what exposes it.
A good prevention for the real world is the opposite — `max_fails` and
`fail_timeout`, so a dead member removes itself.

**Why it is level 4.** Not because the cause is deep — `nginx -T` finds it in
one command — but because every instinct the symptom provokes is wrong. A single
`curl` passes four times in five, so the natural investigation produces evidence
*against* there being a fault at all, and the reporter's "every time I open a
terminal it works" is literally true.

**The skill being taught.** Turning an intermittent report into a measurement.
Fifty requests in a loop takes two seconds and converts "it feels like one in
five" into a rate you can reason about — and a rate that is a clean fraction is
itself the clue, because fractions mean round-robin.

**The trap.** Deleting the broken member. The symptom clears immediately, and
two things are now wrong: whatever capacity the third member represented is gone
without a decision, and nobody has established why that address was in the
configuration. `check.sh` asserts the upstream still has its original number of
members, so the passing fix is to repair the member rather than remove it.

The second trap: declaring success on one request. The check makes a hundred
consecutive requests and requires every one to return 200, for the same reason
the brief exists.

**`PROVEN=unproven`, and precisely what that means here.** Against real nginx,
two things were verified: the check's logic (it correctly fails when a member is
deleted, and passes when the member count is intact), and the discovery that
nginx's **default** `proxy_next_upstream` makes a dead member invisible —
thirty requests through a three-member upstream with one dead member returned
thirty 200s.

What is **not** verified is the break producing visible 502s. Adding
`proxy_next_upstream off` did not reproduce the failures in the test harness and
the cause was not isolated before time ran out. **First thing to check on the
VM:** run `lab start s9-01-one-request-in-five`, then thirty requests in a loop,
and confirm roughly a third of them fail. If they all pass, the break needs
either `proxy_next_upstream off` placed in the right context — confirm with
`nginx -T` that the directive is actually inside the `/api/` location — or a
third member that *answers* with a 500 rather than refusing the connection,
since nginx does not retry an HTTP 500 by default.
