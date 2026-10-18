# s7-04 — author notes

**What this mission is really teaching.** That the threat model for backups is
not disk failure — that is what everyone designs for — but an attacker, or a
mistake, with the credentials your backup job uses. Encryption does not help:
the attacker does not need to read the backups, only to delete them. This is the
single most common reason organisations with working backups still pay a ransom.

**Why it is level 4.** Not because any command is hard, but because the
requirements fight each other. Append-only breaks pruning, because pruning is
deletion. Immutable files break restic's index rewriting. Making it work means
understanding which operations the backup tool actually needs, and moving
retention to the side that is allowed to delete — which is a design decision,
not a flag.

**The honest limit, stated in the brief.** `chattr +a`, a separate owner, or a
local REST server are not what a real provider gives you, and the brief says so
while naming the real equivalents. What transfers is that the writer must not be
the deleter; the implementation is always local to the platform.

**The trap.** Making it *feel* safer. `chmod -w` on the directory, or `chattr
+i` on a few files, or an rclone config with a read-only remote — each of these
produces something that looks hardened and that root can undo in one command
without being told. `check.sh` therefore performs the deletion **as root** and
requires it to fail: the only passing configuration is one where the machine
genuinely cannot destroy its own backups, not one where it has been asked
politely not to.

The second half of the trap is forgetting item 3. An append-only destination
that silently breaks the next backup is strictly worse than what you started
with — you now have an archive that cannot be deleted *and* cannot be added to.
The check requires a new snapshot to still be creatable.

**`PROVEN=unproven`.** It needs a real repository and real file attributes on a
real filesystem; `chattr` behaviour in particular differs on overlayfs, so a
container result would be misleading rather than merely incomplete.
