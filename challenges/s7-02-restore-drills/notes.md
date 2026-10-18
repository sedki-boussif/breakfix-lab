# s7-02 — author notes

**What this mission is really teaching.** That "we have backups" and "we can
restore" are different claims, and only the second one matters. The three drills
escalate deliberately: a file proves the archive is readable, a database proves
the *content* is right, and a fresh machine proves the *procedure* is complete —
that nothing needed was only in the head of whoever set it up.

**Why the fingerprint, again.** Comparing a restore against the live database is
the mistake this mission exists to prevent. The live database has moved on; the
backup has not. Row counts captured at backup time, stored beside the archive,
are the only thing that can tell you whether a restore returned what was
actually in it.

**Why timing is part of the standard.** A recovery time objective nobody has
measured is a guess, and under pressure a guess becomes a promise. The drill
turns it into a number. The number is usually worse than the assumption, and
discovering that on a quiet afternoon is the entire value.

**The honest gap, stated in the brief.** Restoring onto the machine that made
the backup proves the archive is readable and nothing else. The brief says to do
the third drill on a machine that has never seen the data, and to be explicit in
the report when that is not possible — because the difference between those two
is exactly what s8-02 later tests for real.

**No trap.** Everything that could be a trap here fails the standard outright:
comparing against the live database fails the fingerprint assertion, and
restoring over the live data fails the untouched assertion.

**`PROVEN=unproven`.** It needs a real restic repository with real snapshots and
a real fingerprint. Left for the VM.
