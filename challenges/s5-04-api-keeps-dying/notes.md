# s5-04 — author notes

**Determinism was the design problem, and how it was solved.** The original
specification said "a memory hog plus a low cgroup limit, so the OOM killer picks
the API". That is not reliable: the *global* OOM killer chooses by `oom_score`,
which weighs resident size, `oom_score_adj` and timing, so the victim depends on
which process happens to be biggest at the moment memory runs out. On a 4 GB VM
with a hog, PostgreSQL or the frontend build is as likely to be chosen as the
API, and a challenge that picks the right victim three times in five is worse
than no challenge.

So the fault is **a low memory limit on the API's own cgroup** —
`mem_limit: 48m` in compose, `MemoryMax=48M` in a systemd drop-in. The kill is
then performed by the *cgroup* OOM killer, inside a cgroup whose only members are
the API's own processes, so the victim is the API every single time, by
construction rather than by luck. The kernel log says
`Memory cgroup out of memory`, naming that cgroup, which is also better evidence
than a global OOM line.

The memory hog is kept, bounded at 256 MB and deliberately *not* growing, and
demoted to its proper job: a red herring. It explains why the box feels slow
today, it is the first thing anyone will blame, and killing it changes nothing —
because a limit inside the API's cgroup has nothing to do with free memory on the
host. `check.sh` requires both the hog gone and the API surviving, so fixing only
the obvious one fails.

**Why the reporter is a developer with a confident wrong theory.** The
timestamps are real and useful; the inference — a connection-pool problem — is
wrong, and the requested remedy (bump the pool size) would consume *more* memory
and make the kills more frequent. The genuinely relevant detail, "the box feels
sluggish, probably the indexer", is thrown away as an aside, which is exactly how
the useful fact arrives in practice.

**The trap.** Two, both refused:

1. **Killing the hog** and declaring victory. The box gets faster, the API keeps
   dying. Caught because the check requires the API to survive a window without
   its restart counter moving.
2. **Restarting the API.** It is healthy for a few minutes, which matches the
   reported pattern well enough to be convincing. Caught by the same window.

**The positive controls.** Two absence claims, each proved:

- *The hog is gone.* The detector matches the process by the name it runs under,
  so the control starts a harmless process under the same name, requires the
  detector to find it, kills it, and only then asserts absence. This proves the
  pattern actually matches something — a `pgrep` pattern with a typo in it would
  otherwise pass for ever.
- *No OOM kills since the fix.* The detector looks for new cgroup-OOM lines in
  the kernel log after a mark. The control creates its own throwaway cgroup with
  an 8 MB limit, allocates 64 MB inside it, and requires the detector to see the
  resulting kill. Cleanup for a log-based control is to advance the mark past the
  planted event rather than to delete anything, because a kernel log is
  append-only — that is noted here because it is the one place the control
  protocol differs.

**Cost.** The survival window is `S5_SURVIVE_SECONDS`, default 180. The
specification said ten minutes; three is enough when it is paired with a restart
counter that must not move and a kernel log that must stay quiet, and it keeps
`make test` usable. Raise it in `lab.conf` for a harder run.
