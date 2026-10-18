# s7-01 — author notes

**What this mission is really teaching.** Not how to run `restic` — the manual
does that — but the five things that distinguish a backup from a copy:
somewhere else, encrypted, pruned, scheduled, and *monitored*. Most people stop
at the first two, and the one that saves them is the fifth.

**Why the dead-man's-switch is non-negotiable.** Every other property of a
backup system fails loudly: a failed `restic backup` prints an error. The one
that fails silently is the system stopping altogether, which is why s7-05 exists
and why this mission is checked on it. A backup you are not told about is a
backup you will discover the state of on the worst day.

**Why a fingerprint.** A restore that produces *wrong* data silently is worse
than one that fails: you believe you have recovered. Row counts taken at backup
time, stored beside the archive, turn "the restore completed" into "the restore
returned what was backed up". s7-02 and s7-03 both check against it.

**Off-VM is simulated, and the brief says so.** `/srv/lab-offsite` is a separate
filesystem on the same machine. That is honest about what it does and does not
prove: it survives a full local disk and a deleted local repository — which is
what s7-03 tests — and it does not survive the machine. The brief says the
pattern is the lesson so that the gap is visible rather than pretended away.

**No trap.** Every shortcut here fails the standard directly: a backup with no
off-site copy fails assertion 1, an unencrypted one fails 2, a cron line in your
history fails 4. There is nothing that makes the symptom go away while leaving
the cause, because there is no symptom — this is a mission.

**`PROVEN=unproven`, and why it stays that way here.** The check needs a real
`restic` repository, a real systemd timer, and a real second filesystem. A
container harness for that would be building the mission rather than testing it.
It is written, linted, and left for the VM.
