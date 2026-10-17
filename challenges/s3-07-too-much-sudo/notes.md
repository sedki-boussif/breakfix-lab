# s3-07 — author notes

**What the fault really is.** A drop-in file under `/etc/sudoers.d/` granting
`dev1 ALL=(ALL) NOPASSWD: ALL`. It is not a malfunction; it is a standing grant
that nobody will notice until it is used, by the account's owner or by whoever
gets hold of it.

**Why it is realistic.** It is the fastest way to make someone's deploy work, it
is what every forum answer suggests, and it is permanent because nothing ever
fails to remind you about it. The business need — restart nginx after a deploy —
is entirely legitimate, which is what makes the over-grant survive review.

**Why the reporter is an auditor.** No symptom exists, so there can be no user
report, and the brief has to establish its own stakes: a policy clause, a stated
need, and a remediation that must be evidenced. It is also the only voice in
Stage 3 that is cold — no urgency, no apology, no confusion — and reading a
finding is a real and separate skill from reading a ticket.

**The trap.** Granting `NOPASSWD: /usr/bin/systemctl` — or worse,
`/usr/bin/systemctl *` — instead of the exact command. It looks narrow, passes a
casual read, and in fact still allows `systemctl mask ssh`, `systemctl stop
postgresql`, or starting a unit of the account's own making. sudo matches
arguments literally, so the grant must name them:
`/usr/bin/systemctl restart nginx`. `check.sh` enforces both halves — nginx can
be restarted, another unit cannot, and `sudo -l` lists exactly one command — so a
wildcard grant fails.

A second, subtler shortcut: removing the drop-in file but leaving `dev1` in the
`sudo` group, which inherits the distribution's `%sudo ALL=(ALL:ALL) ALL`. The
account can then still do everything, with a password. `sudo -l -U dev1` shows
it, which is why the check reads sudo's own view rather than the files.

**A third shortcut, found while testing this.** Granting a path that sudo does
not resolve to. sudo uses `secure_path`, not the user's `PATH`, so a grant of
`/usr/bin/systemctl` is dead if sudo resolves `systemctl` to
`/usr/local/bin/systemctl` first. The grant reads correctly, `visudo -c` passes,
`sudo -l` lists it, and the command is still denied. `check.sh` catches it
because it runs the command as the account rather than reading the grant — which
is the general principle: test the behaviour, not the configuration.

**Level 1.** One cause, in plain sight, with no diagnosis to do. It earns its
place because the fix is easy to get subtly wrong and because `sudo -l` is the
only authority worth consulting.

**Safety.** `break.sh` creates `dev1` with no password and no authorized key, so
the account cannot be used to log in over SSH, and it touches nothing about SSH
configuration. `reset.sh` removes the drop-in and deletes the account only if
`break.sh` created it.
