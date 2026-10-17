# s3-01 — The leave app returns 502

## Symptom
From about 14:00, the leave application returns `502 Bad Gateway` to everyone,
on every device and from outside the office. The other two apps are unaffected.
Nobody reports a deployment that day.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl -i http://127.0.0.1:8081/etoile-formation-conge/` | Connection refused from the VM itself, not a 502 | Ruled out nginx, the TLS layer, DNS and anything between the laptop and the VM. The failure is behind the proxy |
| 2 | `ss -ltnp \| grep 8081` | Nothing listening | Ruled out "the app is slow" and "the app is wedged". There is no process to be slow |
| 3 | `systemctl status leaves` | `failed (Result: exit-code)`, and `status=203/EXEC` | Ruled out the application itself: 203/EXEC is systemd saying it could not execute the file. No Python ran, so no settings, database or migration can be at fault |
| 4 | `journalctl -u leaves -n 50` | `Failed to execute /opt/leaves/venv/bin/gunicorn: No such file or directory`, repeated until the start limit | Ruled out a transient failure. It never started once |
| 5 | `systemctl cat leaves` | `ExecStart=/opt/leaves/venv/bin/gunicorn …` | — |
| 6 | `ls -l /opt/leaves/venv/bin/gunicorn` then `ls -l /opt/leaves/.venv/bin/gunicorn` | The first does not exist; the second does | Confirms it: the unit names a path that is one character different from the real one |

**Dead end worth recording.** Checking `nginx -t` and the nginx error log first is
a reasonable instinct and costs two minutes. The error log says
`connect() failed (111: Connection refused) while connecting to upstream`, which
is nginx correctly reporting someone else's failure. A 502 is almost never nginx.

## Root cause
The unit's `ExecStart` pointed at `/opt/leaves/venv/bin/gunicorn` instead of
`/opt/leaves/.venv/bin/gunicorn` — one missing dot — so systemd could not
execute it and the service died instantly, leaving nothing on port 8081 for
nginx to reach.

## Fix
Correct the path in the unit, reload systemd's view of it, and start the service:

```bash
sudo sed -i 's|/opt/leaves/venv/bin/gunicorn|/opt/leaves/.venv/bin/gunicorn|' \
  /etc/systemd/system/leaves.service
sudo systemctl daemon-reload
sudo systemctl reset-failed leaves    # it hit its start limit while failing
sudo systemctl restart leaves
```

`reset-failed` matters: a unit that has exhausted `StartLimitBurst` refuses to
start again until the counter is cleared, which looks like the fix not working.

Why this rather than a workaround: running
`/opt/leaves/.venv/bin/gunicorn … &` by hand serves the page immediately and
leaves the cause in place. That process dies with the shell it was started from
and does not come back after a reboot, so the app would fail again at the next
restart with no new change to blame.

## Verification
`systemctl is-active leaves` reports active; the app answers 200 both directly on
8081 and through the host nginx with the vhost's `Host` header; and — the part
that matters — `systemctl restart leaves` followed by another request still
answers 200, proving the fix is in the unit rather than in a process someone
started.

## Prevention
- **A config test before reload.** `systemd-analyze verify /etc/systemd/system/leaves.service`
  reports an `ExecStart` that does not exist, and costs nothing in a deploy script.
- **Monitor the service, not just the page.** The watchdog in s6-04 checks
  `systemctl is-active` and alerts on the state *change*; this fault would have
  been caught the moment the service was restarted rather than hours later by HR.
- **Stop editing unit files by hand.** Whatever rebuilt the virtualenv should
  rewrite the unit from the same template, so the venv path exists in one place.
- **Know that `daemon-reload` restarts nothing.** The most useful habit here:
  after changing a unit, `systemctl restart` it immediately and watch it come
  back. A unit that is only reloaded is a fault scheduled for later.

## What I did not know before this
`status=203/EXEC` is a specific and very narrow failure — systemd could not
execute the binary at all — so it eliminates the whole application in one step.
And a unit that has hit its start limit stays down until `reset-failed`, which
can make a correct fix look like it failed.
