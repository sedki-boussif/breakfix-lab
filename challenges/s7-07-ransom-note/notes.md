# s7-07 — author notes

**What the break really does.** Every file in the uploads volume is renamed to a
random hex string with a `.locked` suffix and its contents overwritten with
random bytes; a ransom note is written beside them; and the **local** restic
repository is deleted. The off-site copy is deliberately left alone — the
challenge is whether s7-01 produced something that works, and this is the day it
is worth having done.

**Why irreversible.** The uploads are genuinely destroyed. `reset.sh` restores
the local repository from a copy taken before the break and removes the note and
the scrambled files, but it cannot bring the originals back, because nothing
kept them. That is the honest version: a ransomware drill where `reset.sh`
undoes the damage teaches that ransomware is survivable by undo, which is the
opposite of true. The brief leads with the preconditions for that reason.

**Why the database is left intact.** Two reasons. It makes the first job scoping
rather than despair — the correct early finding is "the database is fine and the
uploads are gone", which halves the recovery. And a drill that destroys
everything is indistinguishable from restoring the snapshot, so there would be
nothing to practise.

**Why the note is quoted in full.** Because every instruction in it is an
instruction not to do the thing that helps: do not restart (so that whatever is
resident stays resident), do not contact your provider (who can see the
outbound traffic), and pay quickly (before you discover you have backups). Being
able to read that as evidence rather than as pressure is most of the skill, and
the brief says so directly rather than leaving it as a trick.

**The trap.** Restoring over the damaged directory without staging. The restore
"works", and the `.locked` files are still sitting there alongside the recovered
ones, so the application sees a mixture and the next person cannot tell what was
recovered from what was not. `check.sh` therefore requires **no `.locked` files
and no ransom note anywhere under the uploads path**, as well as the real files
being back and readable.

The second trap is skipping evidence preservation. It costs nothing and it is
the only record of what happened; the report assertion requires you to say where
you put it.

**`PROVEN=unproven`.** It needs a real restic off-site repository and the real
stages uploads volume. It is also, by the testing policy, not something to
exercise on a development machine: it deletes a backup repository and overwrites
files.
