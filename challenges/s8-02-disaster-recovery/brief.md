**Snapshot required — and this one does not undo.** You are going to delete the
VM. Not break it: delete it, from the hypervisor, with the disk. Then rebuild it
from your Git repository and your backups alone, inside the recovery time you
wrote down in s7-02 before you knew what it would really be.

**What survives, and what does not.** This is the whole exercise, so read it
before you start rather than discovering it at minute forty:

- **Your Git repository survives**, because it is not only on the VM. That is
  where `lab.conf`, `SETUP.md` and your runbooks live.
- **Your backup repository survives** only if "off-site" meant something when
  you built it in s7-01. A second directory on the same disk dies with the
  disk. This drill is where that distinction stops being theoretical.
- **`~/.breakfix-progress` does not survive.** The lab's own record of your
  progress, the timings, the state every `break.sh` wrote — all on the VM, all
  gone. The check for this challenge therefore asks nothing of it, and that is
  deliberate: a recovery procedure that depends on something the disaster
  destroyed is not a recovery procedure.
- **Anything in your head does not survive contact with minute ninety.** Which
  is what s8-03 is for.

**The work:**

1. **Before you delete anything**, `lab start s8-02-disaster-recovery` prints a
   record of what this machine currently is: row counts, listening ports,
   accounts. Save it **off the VM** — your laptop, the Git repo, anywhere the
   deletion cannot reach. You will want it to compare against, and it is the
   first thing people lose.
2. **Confirm that your off-site backup copy is genuinely off this VM**, and
   that you can list its snapshots. If you cannot, stop here: deleting the VM
   now is not a drill, it is data loss with a lesson attached.
3. **Note the wall-clock time, and delete the VM.** Disk and all.
4. **Rebuild**, from the Git repository and the backups, with no snapshot to
   fall back on and nothing to copy from the old machine.
5. **Restore the data from the archive** rather than re-seeding it. Re-seeding
   produces a machine that works and proves nothing: the question is whether
   your backups can bring the data back, and fresh fake data is not the data.
6. **Reboot**, then check — and pass the elapsed minutes to the check, because
   it is the number this whole drill exists to produce.

**The standard this will be checked against** — the full s8-01 acceptance
suite, and then three things it does not ask:

- **Every row count in the archive matches the database now serving**, not just
  one. After a rebuild from backups alone the data has no other source, so a
  count that disagrees anywhere means the recovery lost something.
- **The elapsed time against your objective**, from `S8_RTO_MINUTES` in
  `lab.conf`. The check reports the gap in both directions and only fails on
  one of them — see below.
- **The report names what you had to improvise**, because that list is the
  difference between a runbook and a wish.

**About missing the objective.** Coming in over your RTO fails the check. This
is the one place in the lab where the check holds you to a number you chose
yourself, and the reason it fails rather than warns is that an RTO you quietly
revise upwards after missing it is not an objective, it is a description. If
the number was wrong, the honest move is to change it in `lab.conf`, say so in
the report, and know that you changed it — not to let the check shrug.

**Running the check:**

```
lab check s8-02-disaster-recovery --arm            # after the rebuild
sudo reboot
lab check s8-02-disaster-recovery --minutes 95     # your measured elapsed time
```
