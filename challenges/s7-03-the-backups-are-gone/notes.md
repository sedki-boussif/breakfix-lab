# s7-03 — author notes

**What the faults really are.** Two, deliberately tangled:

1. Every local archive is deleted — the repository directory is gone.
2. The newest off-site snapshot is corrupted: a pack file is truncated, so
   `restic check` reports errors and a restore of `latest` fails.

The data loss is real but bounded: the second-newest off-site snapshot is
intact, and restoring it costs whatever was written between the two.

**Why both.** Either alone is a level-2 inconvenience. Together they produce the
situation backups exist for and nobody rehearses: the obvious copy is gone, the
remaining copy is damaged, and the correct move is to find the newest thing that
is *actually readable* rather than the newest thing that is listed. The 3-2-1
rule earns its keep here or not at all.

**Why the reporter has already intervened — and said so.** He ran `restic
repair` without knowing what it does, which is exactly what a person does at
08:50 with an empty database. The brief does not hide it, because the first
question is "what has already been done to this repository", and a reporter who
volunteers that is a gift. His other useful act was stopping.

**The trap.** Restoring `latest` because it is listed, or trusting `restic
snapshots` as evidence that a snapshot is retrievable. It is not: the index can
list a snapshot whose data is unreadable. `check.sh` compares the restored row
counts against **the fingerprint for the snapshot that was restored**, so a
restore that silently produced a partial or wrong dataset fails even though the
command exited zero.

A second trap: restoring straight over the live database. It fails nothing in
the check — the data would be right — but if the candidate snapshot turns out to
be the damaged one, you have destroyed the only remaining state. The hints say
to stage it; the solution says why.

**What the check really wants.** Not "a restore happened" but three things: the
data is back, it matches the fingerprint of the snapshot it came from, and **the
report states the data loss window actually achieved against the objective**.
The last is the only one that teaches anything, because the number is always
worse than the assumption.

**`PROVEN=unproven`.** It needs a real repository with several snapshots, one of
them deliberately damaged. Left for the VM.
