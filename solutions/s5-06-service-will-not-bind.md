# s5-06 — The service will not bind

## Symptom
After a routine deploy, the leave service will not start. It reports
`[Errno 98] Address already in use` and systemd marks the unit failed. It had
been serving normally until it was stopped for the deploy, and no configuration
was changed.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | the error itself | `[Errno 98] Address already in use` | Ends the diagnosis rather than starting it: the port is taken. Ruled out the templates that were deployed, the database, the configuration and the code |
| 2 | `sudo ss -ltnp \| grep 8081` | `python3`, pid 2471, listening on 127.0.0.1:8081 | The answer, one command in |
| 3 | `ls -l /proc/2471/exe` and `tr '\0' ' ' < /proc/2471/cmdline` | `/usr/bin/python3`, running a short inline script, argv[0] rewritten to `telemetry-agent` | The name was decoration. Not the leave app, not a second gunicorn |
| 4 | `ps -o ppid=,user=,etimes= -p 2471` | Parent 1, root, a few minutes | Started during the deploy window, which is why the restart is what exposed it |
| 5 | `systemctl status leaves` | `failed`, with the same errno in the journal | Confirms the unit never bound rather than binding and dying |

**Dead end worth recording.** Checking whether two gunicorn processes were
running — a plausible cause of the same errno, and `ss` had already answered it.

**The thing not to do.** The reporter offered to reboot. A reboot would very
probably have cleared the squatter and removed every trace of what it was, which
converts a solved incident into one that recurs without explanation.

## Root cause
An unrelated process bound 127.0.0.1:8081 during the few seconds the service was
stopped for the deploy, so gunicorn could not bind when it came back.

## Fix
```bash
sudo ss -ltnp | grep 8081          # record the pid, exe, cmdline and owner first
sudo kill 2471
sudo systemctl reset-failed leaves
sudo systemctl start leaves
sudo ss -ltnp | grep 8081          # the pid should now be inside leaves.service
```

Why not move the application to another port: it starts immediately and leaves
three things wrong. The host nginx still proxies to 8081, so the site stays
broken; the squatter is still running and will take the port again at the next
deploy; and the port in the deployment no longer matches the port in the
configuration, which is a trap for whoever reads it next.

## Verification
`systemctl is-active leaves` is active, the app answers 200, and the pid
listening on 8081 is inside `leaves.service`'s cgroup — which also rules out a
gunicorn someone started by hand on the right port. Then a restart, to prove it
binds repeatably rather than having won a race once.

## Prevention
- **Find out what the squatter was.** A process with a rewritten argv[0] binding
  an application port is either someone's leftover or something worth escalating.
  The answer changes whether this was an incident or a security incident.
- **Bind to the address, not just the port**, and reserve the port properly: a
  systemd socket unit holds it across restarts so nothing can slip in during the
  gap.
- **Alert on the unit, not just the page.** The service was failed for minutes
  before a human noticed.
- **`ss -ltnp` before every deploy that restarts a service** is a two-second
  habit that would have caught it in the window.

## What I did not know before this
How small the window is. A service that is stopped for three seconds is a port
that is free for three seconds, and anything on the machine that retries a bind
can take it. Also that `[Errno 98]` is worth treating as a complete answer rather
than a starting point — it is one of the few errors that leaves nothing to infer.
