# s4-04 — author notes

**Why this is a mission and not an incident.** There is nothing to diagnose: the
behaviour is by design and documented. What is missing is *belief*. Almost
everyone who runs Docker behind ufw assumes the firewall applies, and the only
reliable cure is to publish a port, deny it, and watch it answer from another
machine.

**Why it targets `stages`.** It is the only containerised application in the lab
as built — `leaves` and `nurse` run as gunicorn under systemd, because neither
public repository ships a Dockerfile. So `stages` is the only place where
published container ports are real, and the demonstration needs a real one.

**The mechanism, which is the actual lesson.** `ufw` manages `ufw-input`,
reached from the kernel's `INPUT` chain. Traffic to a published container port
is **forwarded** to the container, not delivered to the host, so it traverses
`FORWARD` → `DOCKER-USER` → `DOCKER` and never meets `ufw-input` at all.
Docker's `DOCKER` chain is rewritten whenever it pleases; `DOCKER-USER` is the
chain Docker promises not to touch, which is why it is the supported place for
rules that must apply to container traffic.

**Two fixes, and they are not equivalent.** Binding to loopback *removes* the
exposure, which is strictly better and is the right default. `DOCKER-USER` is
for the case where the port genuinely must be published and filtered. The
mission requires both, because knowing only the second encourages publishing
things that should not be published.

**The trap.** Testing from the VM. `curl http://127.0.0.1:9090/` works in every
configuration and proves nothing — the hole is only visible from another host,
and so is the fix. `check.sh` tests from the LAN address for that reason, and
will tell you to set `LAB_LAN_IP` if it is not set.

The second trap: an `iptables -I DOCKER-USER` rule that does not survive a
reboot. It passes the check and is gone next week; the report has to say how it
was persisted.

**`PROVEN=unproven`.** It needs real Docker publishing, real ufw, a real LAN
address and a second host. A container shares the host's network namespace, so
every part of this would be a fiction here.
