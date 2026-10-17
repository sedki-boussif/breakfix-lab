# s3-01 — author notes

**What the fault really is.** The `ExecStart=` line in the gunicorn unit is
rewritten to a path that does not exist — `/opt/leaves/venv/bin/gunicorn`
instead of `/opt/leaves/.venv/bin/gunicorn`, one missing dot. systemd cannot
execute it, so the service dies instantly with `status=203/EXEC`, nothing
listens on 8081, and the nginx in front returns 502. In compose mode the same
shape is produced with a `compose.override.yaml` whose `command:` names a WSGI
module that was never there.

**Why it is realistic, and why "since about two o'clock".** This is what a
virtualenv rebuild leaves behind. Someone recreates the venv under a slightly
different name, or a deploy script writes the unit from a template with the
wrong variable, and **nothing breaks at the time**: `systemctl daemon-reload`
does not restart anything, so the gunicorn that is already running keeps serving
quite happily on the old binary. The app only dies at the next restart — a log
rotation that signals the service, a package upgrade, a reboot — which is why
the symptom appears hours after the change and nobody connects the two. That gap
is the lesson: "nothing was deployed today" is true and still not an alibi.

**Why level 2.** One cause, and the evidence is three commands deep: 502 →
`systemctl status` → `ExecStart`. There is nothing hidden, but you do have to
know that 502 means "ask the upstream" rather than "look at nginx", and that
203/EXEC is a different class of failure from an application error.

**The trap.** Running gunicorn by hand fixes the symptom and leaves the cause in
place. `check.sh` restarts the service through the service manager for exactly
this reason, so a hand-started process cannot pass. This is deliberate: the
same instinct is what makes a server work until the next reboot and then not.

**Both modes.** `break.sh` takes the unit path from
`systemctl show -p FragmentPath` rather than assuming `/etc/systemd/system`, and
only breaks an `ExecStart` whose binary currently exists, so running it twice
does not deepen the damage. In compose mode it writes an override file, backing
up any override that was already there and recording whether it created one, so
`reset.sh` removes its own and restores the user's.
