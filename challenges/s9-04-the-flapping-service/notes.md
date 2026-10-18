# s9-04 — author notes

**What the fault really is.** The leave service exits every couple of minutes
and `Restart=on-failure` brings it straight back. Sessions live in process
memory, so every restart logs users out mid-task. Any status check between
restarts sees a healthy service.

**Why it is level 3 rather than 2.** The cause is hidden from the symptom by
the restart policy. A restart policy is good practice and here it is also the
thing that conceals the fault: without it the service would be *down* and
someone would have noticed in minutes.

**The two reporters.** HR describes the symptom accurately and dismisses it as
annoying rather than broken; Nizar checked twice, correctly, and found nothing —
because status is a snapshot and this fault is only visible in history. Both
observations are right and the conclusion drawn from them is wrong.

**The instrument that answers it.** `NRestarts` is a counter, not a state. It is
the single most under-used number in systemd, and it turns "it looks fine" into
"it has restarted forty times since Tuesday" in one command.

**The trap.** Restarting the service. It comes back, everything looks healthy,
and the counter resets to zero if the unit is reloaded — so the evidence is
destroyed and the fault returns in two minutes. `check.sh` therefore watches the
counter **over a window** and requires the current main process to have been
alive longer than `S9_04_MIN_UPTIME`, so a service that has just been restarted
cannot pass.

The second trap: raising `RestartSec` so it flaps more slowly. The symptom
becomes rarer and the cause is untouched.

**`PROVEN=unproven`.** It needs real systemd restart accounting — `NRestarts`
and `ActiveEnterTimestamp` — against a real service. The stand-in service
manager used elsewhere in this lab does not implement restart policies, and
simulating one would be testing the simulation.
