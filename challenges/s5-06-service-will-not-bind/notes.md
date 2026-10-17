# s5-06 — author notes

**What the fault really is.** A process unrelated to the application is bound to
the port the service needs, so gunicorn cannot bind and systemd marks the unit
failed. The squatter took the port during the few seconds the service was
stopped for the deploy — which is why the restart is what exposed it and why
"I did not change anything" is true.

**Why it is realistic.** Anything that binds an ephemeral or a convenience port
can land on yours: a monitoring agent, a developer's test server left running, a
second copy of the app started by hand weeks ago, a container publishing to the
same port. The window is always a restart, which is why the fault arrives
attributed to the deploy.

**Why the reporter is a colleague reading his screen.** He has the single most
valuable piece of evidence — the exact errno — and no interpretation of it at
all. That is a genuinely common and pleasant kind of report, and it teaches
something different from the vague ones: the skill is recognising that
`[Errno 98]` ends the diagnosis rather than starting it. His offer to reboot is
the real hazard in the brief, because a reboot would probably clear the squatter
and destroy every trace of what it was.

**The trap.** Moving the application to another port. The service starts
immediately, the error goes away, and three things are now wrong: the host nginx
is still proxying to the old port so the site is still broken, the squatter is
still running, and the port assignment in the deployment no longer matches the
one in the configuration. `check.sh` requires the service to be listening on the
port named in `lab.conf`, and requires the listening pid to be inside the
service's own cgroup — so a hand-started gunicorn on the right port does not pass
either.

**No absence assertion, and why.** The first draft of this check had one — "no
foreign process is holding the port" — with its detector pointed at a spare port
where a control could safely be planted. It passed while the squatter was still
holding 8081, because the assertion never looked at 8081 at all. It proved the
detector worked and nothing else, which is the same failure as a vacuous PASS
wearing a control as a disguise.

The claim here is positive instead, and stronger: the process listening on the
configured port must be the service, by cgroup membership or by being the unit's
main process or a child of it. That fails if a squatter holds the port, if
nothing holds it, or if gunicorn was started by hand — all three of the ways this
can be wrongly "fixed". A positive claim is its own evidence; no control is
needed, and inventing one would have hidden the hole rather than closing it.

**Level 2.** One cause, named by the error message, found with one command. It
earns its place because the obvious fix is the wrong one and because the reporter
is about to destroy the evidence.
