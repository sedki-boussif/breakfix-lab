# s5-01 — author notes

**What the fault really is.** A single pre-allocated file of a few hundred
megabytes under `.cache/.import-spool/` on the uploads filesystem, large enough
to take it past 95%. Nothing else is touched.

**Why it is in a dot-directory.** So that the first command most people run —
`du -sh /path/*` — misses it completely, because the shell glob does not match
dotfiles. That single gap between `df` and `du` is the whole diagnostic lesson,
and it is the reason the reporter concluded `df` was lying.

**Which filesystem, and why it is bounded.** `/srv/lab-scratch/uploads` is a
512 MB loopback filesystem created by `break.sh` and reformatted by `reset.sh`.
A fill on the root volume would be more realistic and is not worth the risk: if
this ever ran on a machine it should not have, a bounded loop image is
recoverable and a full root volume is not. The brief names the mount explicitly
because "the disk is full" on a host with several mounts is a different
investigation depending on which one.

**Why the reporter has already intervened.** Two useful effects. His cleanup
destroyed evidence — the logs he deleted would have shown what was writing — and
his wrong conclusion ("df is lying") is the exact conclusion the dot-directory
gap produces. The brief also hands over a *command that was run* rather than a
symptom, so the first move is to notice what that command cannot see.

**The trap.** Freeing space by deleting something else — more logs, a package
cache, an old backup. The percentage falls, the ticket closes, and the file that
filled the volume is still there to do it again. `check.sh` asserts the large
file is **absent**, not merely that usage is under 80%, so a fix that only moves
the number fails.

**The positive control.** The detector is "find a file of more than 64 MB on this
filesystem". To prove it works, `check.sh` creates a 128 MB **sparse** file with
`truncate`, which has that apparent size while occupying no blocks, requires the
detector to find it, removes it, and only then asserts absence. A sparse control
costs nothing even on a filesystem that is nearly full — which matters, because a
control that needs real space cannot run on the filesystem it is testing.

**A trap that is not fully enforceable.** Moving the file to another filesystem
rather than deleting it. The affected volume drops below 80% and the file is gone
from it, so the check passes. Catching it would mean searching every filesystem
on the host for a file of that size, which produces false failures on anything
legitimately large. It is named here and in the solution instead.
