**The goal.** Make the off-site copy something this machine can write to and
cannot destroy.

Every backup you have built so far shares one weakness: the credentials and the
access that let this VM *write* backups also let it *delete* them. Anything that
gets root here — and s7-06 and s7-07 assume something did — can empty the
off-site repository in one command, and ransomware does exactly that first.

**The standard this will be checked against:**

1. The off-site repository is **append-only from this VM**: new snapshots can be
   written, and existing data cannot be removed or overwritten.
2. **Prove it, from this VM, as root**: attempt to delete an old archive and
   have the attempt refused. The archive is still there afterwards.
3. **Backups still work.** An append-only destination that breaks the backup is
   not a solution, so a new snapshot must still be creatable afterwards.
4. **Pruning still happens somewhere.** Append-only means this machine cannot
   prune, so retention has to be enforced from the other side — by whatever
   owns the destination. Say in the report where that now lives, and what would
   happen if it stopped.

**Off-VM is simulated locally**, as everywhere in this lab: the destination is a
separate filesystem on this machine. The mechanism you use to make it
append-only here will not be the mechanism a real provider gives you — S3 object
lock, a restic REST server in `--append-only` mode, a separate user over SSH with
a forced command. What transfers is the *shape*: the writer cannot be the
deleter.
