# s4-05 — author notes

**What this mission is really teaching.** Not lynis. Two things: that
"hardened" has to be a number with a date on it before improvement means
anything, and that a scanner's suggestion list requires judgement rather than
obedience.

**Why "only what you agree with".** A hardening index rewards changes
indiscriminately, and a machine configured to maximise it is often a machine
that cannot do its job: disabling kernel modules a container runtime needs,
mount options that break Docker, password policies on an account that only has
keys. The report's list of *rejections* is the part worth reading in a year.

**Why SSH is verified by `sshd -T`.** Reading `sshd_config` proves nothing on
Ubuntu, where `sshd_config.d/*.conf` is included from the top and first value
wins — the same trap SETUP.md's step 2 was fixed for. `sshd -T` prints the
effective configuration, which is the only evidence.

**Why the port list is matched exactly, in both directions.** An unexpected
listener is the obvious finding. A *missing* expected port means something was
hardened into uselessness, and a score that went up while an application went
down is exactly the failure mode this mission warns about.

**The trap.** Chasing the number. It is possible to raise the index by several
points with changes that do nothing for this machine's actual exposure, and the
check deliberately asserts three concrete properties alongside the score so that
the score alone cannot carry a pass.

**`PROVEN=unproven`.** It needs lynis, a real sshd, and a real port list.
