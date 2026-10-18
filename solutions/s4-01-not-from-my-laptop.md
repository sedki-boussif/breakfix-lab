# s4-01 — Reachable from the server, not from my laptop

## Symptom
The leave site is unreachable from users' machines ("can't connect"), while from
the server itself it answers normally and the service is running. A colleague
concluded the reporter's machine was at fault and asked her to reboot.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl -v http://127.0.0.1:8081/etoile-formation-conge/` on the VM | 200 | Everything from the application down to loopback is fine. This is what the colleague tested, and it tests almost nothing about reachability |
| 2 | `curl -v http://$LAB_LAN_IP/etoile-formation-conge/` **on the VM** | Times out | The decisive step: same machine, different path through the kernel. Loopback is exempt from the firewall's input policy; the LAN address is not |
| 3 | `sudo ufw status verbose` | `active`, default deny incoming — and an explicit `DENY` for 80 | Found it |
| 4 | `sudo ufw status numbered` | The DENY sits at position 1, before the ALLOW | Explains why the ALLOW looks present and does nothing: ufw is first-match |
| 5 | `sudo iptables -L ufw-user-input -n -v` | The compiled rules in order | Confirms it at the layer that actually decides |

**Dead end worth recording.** Checking DNS on the reporter's machine, as
suggested. Thirty seconds to eliminate with `getent hosts conge.lab.invalid`
from her laptop, and worth doing only to be able to say it was eliminated.

## Root cause
A ufw rule denying tcp/80 inserted *before* the allow rule. Loopback traffic
does not traverse the filtered chain, so every test run on the server passed.

## Fix
```bash
sudo ufw status numbered          # find the DENY's number
sudo ufw --force delete <n>
sudo ufw status verbose           # default deny incoming, 22/80/443 allowed
curl -fsS -o /dev/null -w '%{http_code}\n' \
  -H 'Host: conge.lab.invalid' "http://$LAB_LAN_IP/etoile-formation-conge/"
```

Why not `ufw disable`: it clears the symptom in one command and leaves the
machine with no inbound filtering at all, which is a worse incident than the one
being fixed. The check requires default deny inbound with only the expected
ports allowed.

## Verification
The app answers on the **LAN address**, not just loopback; ufw is still enabled
with default deny inbound; no DENY rule shadows the web ports; and the allowed
set matches `EXPECTED_PORTS`.

## Prevention
- **Test from where the user is.** "Works on the server" is not a reachability
  test, and the habit of curling `127.0.0.1` to prove a service is up is the
  single thing that made this take an hour.
- **Monitor from outside the host.** Every check on the VM passed throughout.
- **Review firewall rules as an ordered list**, not as a set. `ufw status
  numbered` is the only view that shows what actually wins.
- **Keep `EXPECTED_PORTS` current** so "what should be open" is written down
  somewhere other than in someone's memory.

## What I did not know before this
That loopback is exempt from ufw's input policy by default, and therefore that
testing a firewall from the machine it protects is close to meaningless. Also
that ufw is strictly first-match, so an ALLOW below a DENY is decoration.
