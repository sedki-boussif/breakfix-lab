# s8-02 — author notes

**What the fault really is.** There is no fault. The incident is the deletion,
and the person performs it, which is unusual enough in this catalogue to be
worth defending: a script that could delete the VM it is running on is a worse
thing for this repo to contain than any break in the catalogue, and the safety
gate would not make it better. `break.sh` therefore does three things and none
of them destructive — it proves the backups could survive the deletion, writes
the record the deletion will destroy, and makes the person type the phrase.

**Why `break.sh` refuses.** If the off-site repository does not answer, or
holds no snapshots, or turns out to be on the root filesystem, then deleting
the VM is not a drill: it is data loss with a lesson attached. The refusal is a
hard exit rather than a warning, because the one thing this challenge must not
do is teach the lesson that way. What it cannot check — whether the "separate
filesystem" is still a file on the same hypervisor — it says out loud instead,
because that judgement needs the person's knowledge of their own setup.

**Why the check reads nothing from before the deletion.** Every other two-phase
challenge in the lab records state and compares against it. This one cannot:
`~/.breakfix-progress` was on the VM. Rather than work around that, the check
is built to need only three things, each of which survives by design — the
archive, `lab.conf` from Git, and the person's own measured number. That
constraint is not a limitation of the check; it is the same constraint the
recovery was under, and making the check live inside it is the cleanest way to
state the lesson: a recovery procedure that depends on something the disaster
destroyed is not a recovery procedure.

**Why every row count and not one.** `accept_backup_restored` compares a single
table, which is enough to prove that a restore happened at all. After a rebuild
from backups alone the data has no other source, so the stronger claim is
available and worth making: every count the archive recorded, against the
database now serving. A restore that silently returns *less* data is the
failure mode that costs more than one which returns nothing, because nothing is
obvious and less is not.

**Why missing the RTO fails rather than warns.** This is the only check in the
lab that holds someone to a number they chose themselves, and it was tempting
to make it advisory. It is not, because an objective that is quietly revised
upward after being missed is not an objective — it is a description of what
happened, written afterwards. Failing makes the revision a deliberate act: edit
`S8_RTO_MINUTES`, say so in the report, and know that you changed it. The check
also says something when the time comes in at under half the objective, because
an RTO with that much slack is either untested optimism in the other direction
or a number that has room to come down.

**Why the loss window is asked for in the report.** It cannot be computed. The
gap between the last archive and the deletion is knowable only to the person
who knows when each happened, and a count that comes back short is evidence of
it rather than a failure of the restore. The hints say this explicitly, because
the instinct on seeing a short count is to assume the restore went wrong and
start over, which wastes the most expensive twenty minutes of the drill.

**The trap.** Re-seeding the data instead of restoring it. `lib/seed.sh` exists,
it works, it produces a machine where every application answers and the suite's
HTTPS, port, access and alert assertions all pass — and it proves nothing at
all about the backups, which is the only question this challenge asks. The
fingerprint comparison is what refuses it: fresh fake data will not match the
counts in the archive, and the closer the seed configuration is to the original
the more confusing the near-miss will be.

The second trap is subtler and catches people who did s7-01 properly: the
password file is not in the repository, by design, which means it is also not in
the backups. If `BACKUP_PASSWORD_FILE` existed only on the deleted VM, the
archive is encrypted with a key that no longer exists. The hints raise it
second, before the deletion rather than after.

**`PROVEN=unproven`, necessarily.** It needs a hypervisor, a VM to delete, and
a real restic repository that genuinely outlives it. A container cannot
honestly exercise any part of that, and the testing policy rules out trying it
on a development machine. What has been verified off the VM: the argument
parsing, the fingerprint comparison's behaviour on absent and present tables,
the RTO comparison in both directions, and that `break.sh` refuses with 97 with
no lab marker before it can prompt for anything.
