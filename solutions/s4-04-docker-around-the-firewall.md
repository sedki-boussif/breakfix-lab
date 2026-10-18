# s4-04 — Docker goes around the firewall

## The goal
Prove that `ufw` does not protect a published Docker port, then fix it two ways.

## Part one — the demonstration

```bash
# publish on all interfaces
cd /opt/stages
# add to a service:  ports: ["9090:80"]
docker compose up -d
sudo ufw deny 9090/tcp
sudo ufw status | grep 9090        # 9090/tcp  DENY  Anywhere
```

Then from the **laptop**:

```bash
curl -v http://<LAB_LAN_IP>:9090/      # answers
```

A port the firewall says is denied, answering from another machine. That is the
whole lesson and it takes two minutes.

## Why it happens

```bash
sudo iptables -L -n -v | less
sudo iptables -t nat -L DOCKER -n
```

`ufw` manages the `ufw-input` chain, reached from the kernel's **INPUT** chain —
traffic destined for the host. A packet for a published container port is
**DNAT'd and forwarded** to the container, so it traverses `PREROUTING` →
`FORWARD` → `DOCKER-USER` → `DOCKER`, and never passes through `ufw-input` at
all. ufw is not being overridden; it is not in the path.

`DOCKER` is rewritten by Docker whenever containers change. `DOCKER-USER` is the
chain Docker promises not to touch, which is why it is the supported place for
rules that must apply to container traffic.

## Part two — the two fixes, which are not equivalent

**1. Bind to loopback (the right default).**

```yaml
ports: ["127.0.0.1:9090:80"]
```

The port is no longer published on the LAN, so there is nothing for a firewall
to have an opinion about. This *removes* the exposure rather than filtering it,
and it is what every other service in this lab already does.

**2. Filter in `DOCKER-USER` (when the port must be published).**

```bash
sudo iptables -I DOCKER-USER -p tcp --dport 9090 -j DROP
```

Rules here are evaluated before Docker's own and survive container restarts.
They do **not** survive a reboot by themselves — I persisted mine by adding the
rule to `/etc/ufw/after.rules` so ufw reinstates it on boot, which keeps all the
firewall state in one place.

## Verification
The port is unreachable from the LAN address; no container publishes on
`0.0.0.0`; the application still answers through nginx; and ufw is still
enabled. Tested from the laptop, because from the VM the hole is invisible in
every configuration.

## What transfers
One sentence: **`ufw` does not filter traffic to published container ports,
because that traffic is forwarded rather than delivered to the host.** Prefer
binding to loopback; use `DOCKER-USER` when you genuinely need the port
published and filtered; and never assume a firewall covers something you have
not tested from off the box.

## What I did not know before this
That this is documented behaviour rather than a bug, and that `DOCKER-USER`
exists precisely because Docker rewrites its own chains and needed somewhere it
would not. Also how convincing a `ufw status` listing is when it is describing a
chain the traffic never enters.
