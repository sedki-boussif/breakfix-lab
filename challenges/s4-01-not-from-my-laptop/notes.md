# s4-01 — author notes

**What the fault really is.** A ufw rule denying the leave application's port,
inserted before the allow rule. Loopback is unaffected — ufw's default input
policy exempts `lo` — so everything tested from the server works and nothing
tested from anywhere else does.

**Why it is level 3.** The cause is hidden from the symptom by *vantage point*
rather than by layering. Every test the person on the server runs passes, so the
evidence they gather argues for the fault being somewhere else, and the natural
next step — "ask her to reboot" — is a dead end that costs an hour.

**Why two reporters.** The whole challenge is the gap between two true
observations. Hers is the one that matters and has no detail; his has all the
detail and the wrong conclusion. Learning to notice that "I curled it on the
server" tests almost nothing about reachability is the point, and it is worth
more than any single command.

**The trap.** `ufw disable`. It makes the symptom disappear immediately, and the
check requires default deny inbound with only expected ports allowed — so
turning the firewall off fails, as does allowing everything. The second trap is
testing the fix from loopback, which never broke: the check fetches via the LAN
address for that reason.

**`PROVEN=unproven`.** It needs real ufw, a real LAN address and a second host
to test from. A container shares the host's network stack and has no meaningful
ufw of its own, so a container result would be misleading rather than partial.
