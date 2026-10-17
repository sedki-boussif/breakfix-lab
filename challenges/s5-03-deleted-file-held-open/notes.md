# s5-03 — author notes

**What the fault really is.** A process holds an open file descriptor on a log
file that has been unlinked. The directory entry is gone, so `du`, `find` and
`ls` cannot see it, but the blocks are not freed until the last descriptor
closes. `df` counts the blocks; nothing else can find them.

**Why it is realistic.** This is what log rotation without a reload does, every
time: the rotator renames or deletes the file, the writer keeps its descriptor,
and the space never comes back until the service is restarted — which is why "we
restarted it and it fixed itself" is such a common and useless post-mortem.

**Which filesystem, and the bound.** `/srv/lab-scratch/logs`, a 512 MB loopback
filesystem, named in the brief. The deleted file is about 400 MB of it, so the
gap between `df` and `du` is unmistakable without risking a real volume.

**Why the reporter is a half-finished handover.** It is the most information-rich
brief in the stage and the most misleading: every individual observation is
correct, the elimination work is genuinely useful, and the conclusion — corrupt
filesystem, needs `fsck` — is wrong. It also plants a constraint that turns out
to be the real lesson: *do not restart the writer*. A brief that only described a
symptom would let the lazy fix pass unnoticed.

**The trap, and it is the point of the challenge.** Killing or restarting the
holding process. It returns the space immediately and is what almost everyone
does. `check.sh` asserts the holding process is **still running**, so the only
passing fix is to truncate through `/proc/<pid>/fd/<n>` — which is the technique
worth owning, because in production that process is often the service you cannot
restart and the evidence you need to keep.

**What the absence claim actually says.** Not "no process holds a deleted file"
— the passing fix leaves the descriptor open on purpose, so that claim would
contradict the requirement that the holder still be running, and could only be
satisfied by killing it. The claim is "no deleted file is **still holding
space**", which is what the incident was about. The detector reads the size
through `/proc/<pid>/fd/<n>`; after a truncate it is zero.

**The positive control.** That is an absence claim, so `check.sh` plants one: it creates a file on the log volume,
opens it with a background process, unlinks it, requires the detector to find a
deleted-and-held file, kills its own planted holder, and only then asserts that
nothing else is holding one. Without that control, a detector that silently
failed — `lsof` missing, the wrong flag, a path that does not match — would pass
every single run while the fault was still there.
