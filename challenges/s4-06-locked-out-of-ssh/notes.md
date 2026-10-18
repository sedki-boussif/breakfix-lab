# s4-06 — author notes

**What the faults really are.** Two halves of one unfinished change:

1. `ssh.socket` has a drop-in setting `ListenStream=` to a new port, so sshd
   listens there and not on 22.
2. `ufw` still allows only 22, so the new port is blocked — and the old port is
   not listening.

The result: nothing can connect on either port. Existing sessions survive,
because socket activation only governs *new* connections, which is why the
change appeared to succeed at the time.

**The Ubuntu 24.04 trap, which is the point.** `Port 2222` in `sshd_config` does
nothing when `ssh.socket` is active. Everyone who has administered Linux for a
decade knows `Port` is where you change this, and on 24.04 that knowledge is
wrong. The challenge makes that discovery expensive once rather than at the worst
possible moment.

**Why `RISK=irreversible`.** `reset.sh` restores the socket drop-in and the
firewall rule, which works while a session is still open. After that there is no
session to run it from: recovery is the console or the snapshot. The brief leads
with the preconditions, `lab start` prints the irreversible warning, and
`break.sh` requires a typed phrase.

**What the break deliberately does not do.** It does not change
`PermitRootLogin`, `PasswordAuthentication`, or `AuthorizedKeysFile`; it does not
touch any key; it does not disable sshd. The fault is reachability, not
authentication, so console recovery is a configuration edit rather than a key
recovery exercise.

**The trap.** Fixing one half. Setting the socket back to 22 works and silently
leaves a `Port 2222` in `sshd_config` that will confuse the next person, and
whichever port is chosen has to be allowed in ufw. `check.sh` asserts a **fresh**
SSH session succeeds, that ufw allows only expected ports, and that the socket
and `sshd_config` **agree on the port** — so a half-fix that happens to work
does not pass.

**`PROVEN=unproven`, and it will stay that way.** It cannot be container-tested:
there is no socket activation, no console, and no second host. It is also, by
the testing policy, exactly the kind of thing never to run on a development
machine.
