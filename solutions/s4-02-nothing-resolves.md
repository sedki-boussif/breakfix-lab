# s4-02 — Nothing resolves

## Symptom
`apt update` and `git clone` hang indefinitely. SSH works, ping by IP works, and
all three applications keep answering — which is what confused the reporter into
thinking the network was fine and something else was wrong.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `ping -c1 192.0.2.1` and `ssh` working | Packets flow | The network is not down. Connectivity and resolution are separate facilities |
| 2 | `getent hosts deb.debian.org` | Hangs, then fails | Narrows it to name resolution in one command |
| 3 | `dig +short deb.debian.org` | No answer, after a timeout | Confirms: queries are being sent somewhere that does not reply |
| 4 | `resolvectl status` | DNS server `192.0.2.53` on the link | Found it. A documentation-range address, which answers nothing by definition |
| 5 | `cat /etc/resolv.conf` | The stub `127.0.0.53` | Important: the stub is correct, so editing this file would be fixing the wrong thing |
| 6 | `grep -n DNS /etc/systemd/resolved.conf` | `DNS=192.0.2.53` | Where the configuration actually lives |

**Why the applications kept working.** Each reaches its database by compose
service name (Docker's embedded DNS, not the host resolver), by `127.0.0.1`, or
over a unix socket. None of those paths consults `/etc/resolv.conf`, which is
why the symptom looked selective and therefore looked like something else.

## Root cause
`systemd-resolved` was configured with a nameserver that does not answer, so
every lookup waited out its timeout and failed. Connectivity was untouched.

## Fix
```bash
sudo sed -i 's/^DNS=.*/DNS=/' /etc/systemd/resolved.conf   # or a real resolver
sudo systemctl restart systemd-resolved
resolvectl status
getent hosts deb.debian.org
```

Why not edit `/etc/resolv.conf`: on a resolved-managed host it is a symlink to a
generated stub, so the edit appears to work and is reverted on the next restart
or reboot. The check restarts `systemd-resolved` before its final assertion for
exactly this reason.

## Verification
A name from `/etc/hosts` resolves, an external name resolves, the stand-in can
still reach its database by name from inside its own network — a resolver fix
that breaks container DNS is a new fault — and names still resolve **after**
`systemctl restart systemd-resolved`.

## Prevention
- **Monitor resolution, not just reachability.** A ping check would have passed
  throughout. A check that resolves a name and alerts on failure costs one line.
- **Two resolvers, and a `FallbackDNS`.** One unreachable resolver should degrade,
  not stop everything.
- **Know where the configuration lives** before an incident:
  `resolvectl status` and `/etc/systemd/resolved.conf`, not `/etc/resolv.conf`.
- **Treat "but the apps are fine" as information**, not as contradiction. It
  localises the fault to things that use names.

## What I did not know before this
How completely container DNS and host DNS are separated — Docker's embedded
resolver means containers keep working while the host cannot look anything up,
which turns a total DNS outage into a confusing partial one. And that on 24.04
`/etc/resolv.conf` is the wrong file to edit, which is the sort of thing that is
obvious once and never again.
