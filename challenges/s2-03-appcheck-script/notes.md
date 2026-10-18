# s2-03 — author notes

**Why the thresholds come from the environment.** This is the whole design
decision of the challenge, and it was not the obvious one. The obvious version
asks for a warning at 80% disk, and the check cannot test it: the lab VM's root
filesystem is not 80% full, filling it to find out is s5-01's job, and a
warning path that has never run is indistinguishable from one that does not
exist. Making the thresholds configurable — `APPCHECK_DISK_PCT`,
`APPCHECK_MEM_MIN_MB`, with defaults — lets the check set them to values that
*must* trip and then require the warning. A threshold you cannot change is a
threshold you cannot test, and that is a general truth about monitoring code
rather than a convenience for this check.

**Why the check stops a real application.** `assert_absent` exists for claims
that something is gone; this is the opposite and stronger shape — the fault is
*created* in the real subject's own domain and the script is required to notice
it. Before asserting anything about the output, the check confirms the
application has actually stopped answering, and reports "without a genuinely
stopped application this assertion would prove nothing either way" if it has
not. That is the same discipline as a planted control, arrived at from the
other direction.

**Why the restore is an EXIT trap.** The check stops an application. If one of
its own assertions misbehaved and the script ended early, a restore at the
bottom of the happy path would leave the lab with `leaves` down and no
indication why. The trap runs on every exit path. It was worth verifying: the
four deliberately-broken implementations used in testing each produced failures
at different points, and `leaves` came back every time.

**Why "the FAIL line names the application" is its own assertion.** The first
thing anyone does with monitoring output is search it for the name of the thing
they have been told is broken. A line reading
`FAIL http://127.0.0.1:8081/etoile-formation-conge/ 000` contains everything
needed to work out which application it is and nothing that can be found by
searching for `leaves`. It is a small thing that makes the difference between
output that answers a question and output that has to be interpreted first.

**Why "it still checked the other two" is its own assertion.** Because the
trap in the brief is subtle and its symptom is a false pass. A script written
as `set -euo pipefail` plus a bare `curl -f` *does* exit non-zero when an
application is down — correctly, by accident, at line four — having never
looked at the other two. Every assertion about the exit code passes. Only
counting the other applications in the output catches it, and a monitoring
script that stops at the first problem is wrong in the specific way that
matters: the first problem is rarely the only one, and a cascade reported as a
single failure is how one bad database takes three teams an hour to diagnose.

**Why the exit code question is left open.** Whether a `WARN` should exit
non-zero genuinely depends on the caller — a timer that pages on non-zero wants
only `FAIL`; a pre-deployment gate wants both. Rather than pick, the brief
requires the decision to be made deliberately and recorded, and the check holds
only `FAIL` to exiting non-zero. An ambiguity named in the brief and resolved in
the report is better than one resolved by the check and never noticed.

**The trap, restated.** `curl -f` without `|| true` under `set -e`. Named in
the brief on purpose: it is the single most common way this script is written
wrongly, the symptom is an exit code that happens to be right, and finding it
by reading the script is much harder than being told to look.

**`PROVEN=mock-systemd`.** The three applications were replaced by three
local HTTP servers and `systemctl` by a shim that can stop and start them, which
exercises `svc_stop`, `svc_start`, the real `curl` path, the stop detection,
the trap and every assertion. What it does not exercise is a real gunicorn
under a real unit, which is why this is mock rather than real. Verified against
a correct implementation (twenty assertions, all passing) and four broken ones:
the bare-curl trap, no timestamps, hard-coded thresholds, and a FAIL line
carrying a URL but no name.
