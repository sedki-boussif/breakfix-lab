# s4-06 — Locked out of SSH

## Symptom
No new SSH connections to the machine, from anywhere: connection refused on 22.
The applications are up and the website works, so the host is healthy. An
unfinished change the previous night was "moving SSH off the default port".

## Investigation

All from the hypervisor console.

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl status ssh ssh.socket` | `ssh.socket` active, listening on **2222** | Not a dead sshd. The listener moved |
| 2 | `sudo ss -ltnp \| grep -i ssh` | 2222 only; nothing on 22 | Confirms it at the socket layer |
| 3 | `sudo ufw status numbered` | 22/tcp ALLOW; **no rule for 2222** | The second half: the new port is listening and blocked |
| 4 | `grep -i '^port' /etc/ssh/sshd_config` | `Port 2222` | Looks like the change that was made |
| 5 | `systemctl cat ssh.socket` | A drop-in: `ListenStream=2222` | **This** is what actually moved the port. `Port` in sshd_config did nothing |
| 6 | `sudo sshd -T \| grep '^port'` | 2222 | What sshd believes, which is not what decides the listener under socket activation |

**The trap, named.** On Ubuntu 24.04 sshd is socket-activated: `ssh.socket`
owns the listening port and starts `ssh.service` per connection. `Port` in
`sshd_config` has **no effect** on what is listened on. Everyone who has
administered Linux for a decade knows `Port` is the answer, and here it is not.

## Root cause
Two halves of one unfinished change: a socket drop-in moved the listener to
2222, and ufw was never updated, so 22 was no longer listening and 2222 was
blocked. Existing sessions survived because socket activation governs only new
connections, which is why the change looked successful when it was made.

## Fix
Decide on a port and make all three agree. I kept 22:

```bash
sudo rm /etc/systemd/system/ssh.socket.d/90-lab.conf
sudo sed -i -E 's/^Port .*/Port 22/' /etc/ssh/sshd_config
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo ufw allow 22/tcp
sudo ss -ltnp | grep -i ssh
```

If keeping 2222 instead, all three change together: `ListenStream=2222`,
`Port 2222`, and `ufw allow 2222/tcp` — plus removing the 22 rule, or you have
left a hole open to nothing.

**Before leaving the console: open a new session from the laptop and keep the
console open until it works.** A fix verified only from the console is not
verified; that is the mistake that turns one outage into two.

## Verification
A fresh TCP connection to the port gets an SSH banner; `ssh.socket` is active;
the socket's `ListenStream` and `sshd -T`'s `port` agree; ufw allows that port
and nothing outside `EXPECTED_PORTS`.

## Prevention
- **Never change the SSH listener without a second way in.** The console, a
  serial console, or a second sshd on another port — arranged *before* the
  change, not after.
- **Change the firewall first, the listener second.** Allowing the new port
  while the old one still works costs nothing and removes the window entirely.
- **Know that `Port` is not where the port lives on 24.04.** Either disable
  socket activation (`systemctl disable --now ssh.socket; systemctl enable --now
  ssh.service`) so `sshd_config` is authoritative again, or accept that the
  socket unit is the place. Pick one and write it down.
- **A config change that only takes effect on restart is a scheduled outage.**
  Restart it immediately, while you are watching, with a way back.

## What I did not know before this
That `sshd_config`'s `Port` is inert under socket activation, and that
`systemctl cat ssh.socket` — including drop-ins — is the only place the truth
is. Also that the surviving session is a trap of its own: it makes a broken
change feel successful for as long as nobody disconnects.
