# s5-05 — author notes

**What the fault really is.** As many busy loops as the VM has cores, each
running under an innocuous name (`apt-cache-gen` by default), owned by an
ordinary user and perfectly killable. Load average climbs to several times the
core count, every request queues behind them, and nothing fails — which is what
makes it hard to report.

**Why it is bounded and polite.** The loops are plain shell `while :; do :; done`
processes at default priority: no `nice -n -20`, no fork bombs, no unkillable
state, and the count is the core count rather than an arbitrary large number. A
break that makes a VM unresponsive to SSH is a trick rather than a lesson, and
§2.6 forbids leaving an unkillable process behind.

**Why the reporter is vague.** This is the most common kind of report and the
least actionable: no timestamps, no error, a confident elimination of the wrong
variable ("not my internet, the BBC loads fine"), and three symptoms that are
really one. The first move is not investigation but measurement — turning "slow"
into a load average and a response time, so that "fixed" can mean something
later.

**The trap.** Renicing the loops instead of killing them. `renice 19` makes the
apps noticeably faster because they now win the scheduler contest, so response
time recovers and the problem looks solved — while the cores stay pinned, the
load average stays high, power and heat stay up, and anything else that wants CPU
still queues. `check.sh` measures **both** load average and response time, so a
renice gets a partial pass and the detector assertion still fails.

A second, lesser trap: killing some of them. With four loops on two cores,
killing two halves the queue and feels like a fix. The detector counts them, so
it fails until none remain.

**The positive control.** "No process is burning a core" is an absence claim, and
the detector is deliberately *name-independent* — it samples `utime + stime` from
`/proc/<pid>/stat` twice, two seconds apart, and flags any process that consumed
more than 80% of a core in between. So the control starts a known busy loop,
requires the detector to find it, kills it, and only then asserts absence. That
control matters more here than anywhere else in the stage, because a
sampling-based detector has many ways to be silently wrong — a parsing error in
the `stat` fields, a window too short to register, a `pgrep` pattern that matches
nothing — and every one of them produces a confident, permanent pass.

**Why the detector does not match on the name.** The name is the thing the
challenge is teaching you to distrust. A detector that looked for
`apt-cache-gen` would pass the moment the loops were renamed, and would teach the
wrong habit to whoever reads it.
