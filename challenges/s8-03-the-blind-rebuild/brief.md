**The goal.** s8-01 again, from a bare Ubuntu 24.04 image — and this time the
only thing you may read is your own runbooks.

**The conditions.** No search, no documentation sites, no manual pages you have
not written, no AI, no notes from this repository other than the ones you wrote
yourself. Specifically allowed, because the alternative is a different exercise:

- **Your own runbooks**, in `S8_RUNBOOK_DIR`. Whatever you wrote after s8-01
  and s8-02.
- **The distribution package mirrors.** `apt` is not research.
- **The machine itself.** `systemctl status`, `journalctl`, `ss`, `sshd -T`,
  `nginx -t`, `--help` on a command you already know exists. Reading the error
  the machine just gave you is the skill; reading the answer someone else wrote
  is not.
- **This repository's `lab.conf`**, because it is configuration, not
  instruction. `SETUP.md` is instruction. Do not open it.

**None of that is enforceable, and no part of this check tries.** It is on your
honour, and the only person the honesty is for is you: a runbook that passes
because you looked something up is a runbook that will fail at 02:00 when you
cannot.

**What is actually being tested.** Not you — the documentation. Every moment you
spend stuck is a gap in a file you wrote, and the gaps are the output of this
exercise. The elapsed time matters much less here than in s8-02; what matters is
the list.

**The work:**

1. `lab start s8-03-the-blind-rebuild` prints the **baseline commit** of your
   runbook repository. Write it down — seven characters — because the check
   compares against it and you are about to delete the machine it was printed
   on.
2. Rebuild from a bare image, reading only what the conditions allow.
3. **When you get stuck, fix the runbook, then carry on.** In that order, and
   commit it. Writing it down afterwards from memory is how the same gap
   survives three rebuilds — you remember that you were stuck, not what you
   needed.
4. Reboot, then check.

**The standard this will be checked against** — the full s8-01 acceptance
suite, plus:

- Your runbook repository has **commits since the baseline**, and the check
  prints the diff. That diff is the deliverable.
- The report records how long it took, and what you had to work out.

**If you genuinely needed nothing**, you still have to commit something: a line
on the runbook recording that it was exercised blind on this date and found
complete. A runbook with a tested-on date is worth more than one without, and
"nothing to add" is a finding that deserves recording rather than a reason to
skip the step.

**Running the check:**

```
lab check s8-03-the-blind-rebuild --arm               # after the rebuild
sudo reboot
lab check s8-03-the-blind-rebuild --since <baseline>
```
