# s6-03 — author notes

**Why the check causes all three conditions instead of reading the rules.**
Reading a configuration and agreeing that it looks correct is the thing this
whole repository is built to avoid. An alert rule that cannot fire looks
identical to one that can — same YAML, same syntax, same reload without
complaint — and the difference only appears on the day it matters. Three
conditions, caused on purpose, with the alert required each time, is the only
version of this assertion worth making.

**Why the alert log and not the monitoring system's own API.** The mission
deliberately does not specify an implementation: Prometheus with Alertmanager,
Netdata, and a shell script on a timer are all defensible at this scale, and
choosing between them is part of the exercise. A check that queried Prometheus
would have chosen for the reader. Requiring a file that is appended to — the
same arrangement as s7-01's dead-man's-switch, for the same reason — keeps the
implementation open while keeping the assertion real. It also tests the half
that actually fails: an alert that evaluates correctly and is delivered nowhere
is the common production outcome, and a rule inspected through the monitoring
system's own API looks perfect in exactly that case.

**Why the quiet period comes first, and is a control rather than a nicety.**
Thirty seconds with nothing wrong, and the log must not grow. The obvious
reason is that monitoring which alerts constantly carries the same information
as monitoring that never alerts. The structural reason matters more: every
assertion below is "a new line appeared matching this pattern", and if lines
appear anyway then all three pass for free. The quiet check is the control for
the rest of the check, and its failure message says so — otherwise someone
would reasonably read it as a style complaint and ignore it.

**Why the disk test builds its own filesystem.** "Any filesystem, not only `/`"
is the hard half of the first rule, and the only honest way to test it is with
a filesystem the monitoring has never seen. `lib/fs.sh` already makes bounded
loopback filesystems for the Stage 5 drills, so the test costs nothing and a
rule hard-coded to `/` — which is what everybody writes first — cannot pass.
It also means nothing on the real root filesystem is ever filled.

**Why the certificate is swapped rather than simulated.** The alternative was
to assert the rule exists and leave it there, which is the weak form this
challenge is built against. So: the real certificate is copied aside, a
seven-day one is generated and installed, the alert is required, and the real
one goes back. Three deliberate limits on the blast radius — the copy is taken
*before* the swap and the swap is refused if the copy failed, the private key
is left alone because the alert is about dates rather than about the key pair,
and the restore runs from an EXIT trap so a failed assertion cannot leave a
short-lived certificate in place. The backup path is printed in the output
either way, so a reader whose run died in a way the trap could not catch knows
where their certificate is.

**Why each alert also has to clear.** A level that never recovers is a level
nobody reads after the second week, and the recovery half is where
state-change logic gets written wrongly — it is easy to alert on a condition
and much easier to forget that it ended. The recovery assertions are absence
claims in shape, but their control is the firing assertion a minute earlier: the
same monitoring, the same log, the same condition. Planted in the real subject's
own domain, which is the test that makes a control worth anything.

**The trap.** Alerting on the state rather than on the change. A rule that
appends a line every evaluation cycle while a condition holds produces several
hundred lines overnight, and the three-hundredth is the one that gets filtered
into a folder nobody opens. It passes the firing assertions here easily and
fails the quiet control, which is the right place for it to fail — the problem
is not that the alert does not work, it is that the channel becomes useless.

A second trap: a rule that fires without saying what for. `ALERT: a thing
happened` satisfies "the log grew" and is worthless at 02:00, so the patterns
require the condition to be named, and the failure message distinguishes "the
log did not grow" from "the log grew and none of it matched" — because those
are different bugs with different fixes.

**`PROVEN=mock-process`.** The monitoring was a shell loop implementing the
three rules with state-change semantics, the applications were small HTTP
servers, and `systemctl` was a shim — but the certificate swap, the
`openssl req -days 7` generation, the date arithmetic and the alert-log
matching were all real.

Verified: a working monitor passes everything the environment allows — the
service alert firing and clearing, the certificate alert firing and clearing,
the certificate swapped and put back, and all three applications still
answering at the end. And a constantly-alerting monitor fails the quiet
control, with the message explaining that it invalidates the assertions below
rather than merely being noisy.

Two cases were set up and not carried to completion, and are recorded here
rather than claimed: a monitor with no certificate rule (which should fail that
alert and still get its certificate back), and an alert that fires without
naming its condition (which should fail on the pattern rather than on the log
not growing). Each run needs about eleven minutes because every alert window
runs to its timeout when nothing matches, and the output is block-buffered
inside the container until it exits, so neither could be observed within the
session. The restore path is exercised by the passing run — the certificate is
swapped and restored there — but the restore specifically after a *failed*
certificate assertion has not been seen to run. It is the first thing to check
on the VM.

The disk assertion could not be exercised, because this Docker host has no loop
devices and `lab_fs_require` cannot make a bounded filesystem. The check
reports that as a failure naming `lab_fs_require` rather than hanging or
skipping silently, which is the correct behaviour and is what was verified in
its place. On the VM, where Stage 5's drills already use this machinery, it will
run.
