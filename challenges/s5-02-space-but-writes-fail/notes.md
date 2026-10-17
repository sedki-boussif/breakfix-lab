# s5-02 — author notes

**What the fault really is.** The spool filesystem has its inodes exhausted by
about two thousand empty files. `df -h` reports 3% of bytes used; `df -i`
reports 100% of inodes used; every `create` fails with `ENOSPC`, which is the
same errno as a genuinely full disk and reads identically in every application
log.

**Why it is only 64 MB with 2048 inodes.** The specification originally called
for a million tiny files. That takes minutes to create, far longer to remove,
makes `reset.sh` the slowest thing in the repo, and turns a twenty-minute drill
into an hour. A 64 MB filesystem formatted with `mkfs.ext4 -N 2048` exhausts
after about two thousand files — seconds to create — and `reset.sh` reformats it,
which is O(1) instead of a traversal of a million directory entries. The
diagnosis is bit-for-bit the same: `df` disagrees with reality, `df -i` explains
it, and the fix is to free inodes rather than bytes.

**Which filesystem.** `/srv/lab-scratch/spool`, named in the brief, because the
whole fault is a disagreement between two numbers *about one filesystem* and the
challenge would be incoherent if it were ambiguous which one.

**Why the reporter describes it wrongly.** She says "the disk is full", which is
false, and then reports the exact measurement that disproves her own conclusion —
3% used — and asks for more disk, which would not help at all, since the inode
count is fixed at format time. This is the most common shape of a real ticket:
correct observations, wrong inference, and a requested remedy that would cost
money and change nothing.

**The trap: there isn't one.** This is deliberate and worth stating. Every way of
making the symptom go away involves freeing inodes, which is the fix; there is no
shortcut that treats the symptom and leaves the cause. Adding space is the only
tempting wrong move and it does not even clear the symptom, so it fails at the
first assertion rather than needing to be refused. Inventing a trap here would be
strained, so the challenge has none.

**The positive control.** The claim "the files are gone" is an absence claim, so
`check.sh` proves its detector first: it creates a small batch of files on the
spool filesystem, requires the inode-consumption detector to notice them,
removes them, and only then asserts that none remain. The batch is small enough
to create on a filesystem that still has inodes free, which is the state the
check runs in.
