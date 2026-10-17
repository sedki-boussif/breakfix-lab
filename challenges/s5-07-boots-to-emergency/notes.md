# s5-07 — author notes

**What the fault really is.** An `/etc/fstab` entry naming a UUID that does not
exist on the machine, without `nofail`. systemd generates a `.mount` unit from
it, the unit is a dependency of `local-fs.target`, the device never appears, the
mount fails, `local-fs.target` fails, and the boot stops in emergency mode with
no network and no services.

**Why it is realistic.** This is what a disk replacement, a cloned VM, a
copy-pasted fstab line, or a `blkid` output transcribed by hand produces. The
lethal detail is the delay: the edit is harmless until the next reboot, which may
be weeks later during patching, by which time nobody connects the two. "The only
thing I did was tidy up the mount table" is the single most informative sentence
in the brief and the reporter does not know it.

**Why it is `RISK=irreversible`.** `reset.sh` restores the fstab it backed up,
which is useful only *before* the reboot. Once the machine is in emergency mode
there is no lab, no network and no `lab` command: the only ways out are the
console or the snapshot. So the brief leads with the preconditions rather than
burying them, `break.sh` requires a typed phrase, and `lab start` prints the
irreversible warning before any of it.

**Why it ships `PROVEN=unproven`, deliberately.** It cannot be container-tested
in any form: a container has no boot, no systemd generator for fstab, and no
console. Nor should it be tested on the development machine, where
`/etc/fstab` decides whether that machine comes up at all. So it is written,
linted, reasoned about, and left for the VM — which is exactly the policy, and
this is the challenge the policy was written for.

**What the break is careful not to do.** It does not touch the existing root
entry, and it does not alter any line that is already there. It **appends** one
entry for a bogus UUID at a lab mount point. That is enough to stop the boot — a
failing non-root mount is sufficient — while leaving the recovery a one-line edit
rather than a rescue-media exercise. Corrupting the root entry would be a more
dramatic challenge and a worse one: the lesson is identical and the recovery is
an hour longer.

**The trap.** Commenting the line out at the console, booting, and stopping
there. The machine comes up, everything works, and nothing has been learned
about *why* a UUID that does not exist was in the file — and if the device was
meant to be there, it is still missing. The check therefore also requires every
remaining fstab entry to be mounted, so a line left in place but unmounted fails,
and `mount -a` to be clean. Commenting out a line for a device that really is
gone is a legitimate fix; leaving a half-fixed fstab is not.

A second trap: `nofail`. Adding it makes the machine boot and is genuinely
correct for an optional device — the solution says so — but it is wrong for a
device that is supposed to be there, and it silently converts a loud failure into
a missing filesystem nobody notices.

**The positive control.** "No mount unit is in a failed state" is an absence
claim. The detector lists failed `.mount` units and compares `/etc/fstab` against
`/proc/mounts`; the control writes a transient `.mount` unit for a deliberately
nonexistent device, starts it so that it fails, requires the detector to see it,
and then stops it, resets its failed state and removes it. Planting that after
boot is safe — a failed mount unit started by hand does not re-enter emergency
mode — which is why the control runs at check time and not at break time.
