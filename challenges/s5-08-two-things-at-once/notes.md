# s5-08 — author notes

**What the faults really are.** Two, unrelated:

1. An invalid directive in the host nginx site file, so nginx fails its config
   test and will not start. Nothing is reachable at all — connection refused
   rather than an error page.
2. The PostgreSQL service is stopped, so the leave app cannot serve. This is
   invisible while nginx is down, because nothing can reach the leave app to
   find out.

**Why the layering matters.** This is the whole point of the challenge. Fixing
nginx does not cause the 502; it *reveals* it. The instinct it attacks is the one
that says "my fix broke something new", which leads people to undo a correct fix.
The ordering is also not symmetric: you cannot find the second fault first,
because the only way to observe it is through the layer that is down.

**Why the reporters disagree.** Deliberately, and both are honest. HR reports a
total outage and infers the server is off — a reasonable reading of a connection
refused, and wrong. Nizar reports a partial recovery and infers the 502 "was
there all along and we could not see it" — nearly right, and the distinction he
misses (unreachable is not the same as invisible) is the lesson. Neither report
is wrong in its facts, and acting on either inference alone sends you the wrong
way.

**The trap.** Stopping at the first fault. nginx starts, the pages load, two of
three applications work, and the ticket looks closeable — Nizar has already
written the sentence that would close it. `check.sh` requires all three
applications to answer, and the database to be running, so a half fix fails on
the half that was never reported.

A second trap: "fixing" the 502 by changing the nginx upstream, or by removing
the leave vhost so the error stops being visible. Both make the symptom go away.
The check asserts the leave app answers through the proxy, not merely that
nothing errors.

**Why level 4.** Two independent faults where fixing one reveals the other, which
is the level-4 definition. Each individually is level 2.

**The positive control.** "No nginx or database unit is failed" is an absence
claim, and the detector is `systemctl --failed` filtered to the two units. The
control plants a transient unit that exits non-zero, requires the detector to
see a failed unit, then clears it — so a detector that misparsed the unit list,
or named a unit that does not exist on this host, fails loudly rather than
reporting a clean machine for ever.
