# s8-01 — author notes

**What this challenge actually is.** An acceptance suite with a brief attached.
Almost nothing in `check.sh` is new: `health_check` is the definition shared
with `lab chaos --check`, the port comparison is s4-05's, the TLS handshake is
s4-03's, the dead-man's-switch drill is s7-01's, and the reboot is s5-07's and
s6-01's two-phase pattern. That is the design, not a shortcut. The thing being
tested is not any single assertion; it is whether all of them hold *at once*,
on one boot, on a machine built in one sitting.

**Why the suite lives in `lib/accept.sh` and not in this check.** All three
rebuilds are scored against the same standard, and a standard that exists in
three copies is three standards within a month. The same reasoning put
`health_check` in `lib/assert.sh` rather than in `lab chaos`: two definitions of
"healthy" would let a chaos round pass while the acceptance suite failed.

**Why both directions on the port list.** `health_check` only looks for ports
that should not be there, because a chaos round that took an application down is
already caught by the application not answering. A rebuild is different: the
characteristic rebuild failure is *omission*, and the second characteristic one
is a development server left running. Checking only for extras catches the
second and misses the first; checking only for absences catches the first and
blesses the second.

**Why the suite performs the restore itself.** "A backup has run" is a claim
about a timer. "A backup has been restored" is a claim about the data, and the
only way to make it is to read the archive back. The suite restores the
fingerprint file — small, bounded, and the one file whose contents can be
compared against something — and compares it against a live row count. The
consequence, which the brief states and the hints repeat, is that the archive
has to be newer than the seed. That is not an artefact of the check; it is the
only version of the claim that means anything.

**Why the alert drill is driven rather than observed.** A quiet alert log is
indistinguishable from a monitoring system that has never worked. So the suite
makes the backups look stale, requires an alert, puts the marker back, and
requires the alerting to go quiet. The recovery half is an absence claim, and
its control is the first half — the same marker, the same watcher, the same log,
thirty seconds earlier. That is a control planted in the real subject's own
domain, which is the condition the two rewritten Stage 5 checks failed to meet.

**The trap.** Building it all by hand and never rebooting. Everything answers,
every assertion in the suite except one passes, and the machine is one power
event away from being a bare image again. `systemctl enable` is the difference
between a server and a demonstration, and nothing reveals which you have built
except stopping the machine. This is s3-06's lesson, and its solution file
already promised that this suite would include a reboot — so it does, as a
two-phase check, because the boot id is the only evidence that cannot be
fabricated by trying harder.

A second trap, smaller and more common: filling in `lab.conf` from what the
suite wants rather than from what the machine is. `EXPECTED_PORTS` copied from
the example file rather than captured from `ss` makes the port assertions
vacuous in exactly the way an unplanted absence control is vacuous. The brief
asks for the lists to be captured when the machine is in the state you are
willing to defend, and that ordering is the entire value of the assertion.

**Why the section headers.** This is the one check in the lab that prints lines
which are not assertions. Sixty consecutive `PASS` lines are unreadable, and a
person reading the output of a capstone wants to know which part of the machine
each block is about. The headers do not interfere with grepping for `PASS` or
`FAIL`, which is the property that matters.

**`PROVEN=unproven`, and it cannot be otherwise.** This needs a bare Ubuntu
24.04 image, a real reboot, a real certificate, a real firewall and a real
restic repository. None of that can be honestly exercised in a container, and
by the testing policy it is not something to attempt on a development machine.
What *has* been verified off-VM is that every script here is shellcheck-clean
and that the suite's own logic — the URL path extraction, the two-directional
port comparison, the boot-id comparison — behaves as intended.
