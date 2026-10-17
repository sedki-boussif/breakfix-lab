# s0-00-smoke — Smoke test: the status page stopped answering

## Symptom
The lab status page stopped loading: the browser hangs and eventually gives up.
It was fine earlier the same day and nobody reports having touched the machine.

## Investigation

| # | Command | What it showed |
|---|---------|----------------|
| 1 | `curl -v http://127.0.0.1:18099/` | Connection refused, immediately. Not a slow page, not a timeout waiting on a backend — nothing is accepting the connection at all. That rules out the content and points at the process. |
| 2 | `ss -ltnp \| grep 18099` | No listener on the port. Confirms it: the server is not running, so this is not a firewall or a proxy problem. |
| 3 | `ls -l ~/.breakfix-progress/state/s0-00-smoke/service/` | The service directory, its `run.sh` wrapper, and a `log` next to it with a recent mtime — something tried to start and wrote to the log. |
| 4 | `tail ~/.breakfix-progress/state/s0-00-smoke/service/log` | `run.sh: line 5: /usr/bin/python3-lab: No such file or directory`. The wrapper is being executed and dying instantly. |
| 5 | `grep ^exec .../run.sh` | `exec /usr/bin/python3-lab -m http.server ...` — the wrapper execs an interpreter that is not installed. |
| 6 | `command -v python3` | `/usr/bin/python3` exists. So the interpreter is there, under the name the wrapper is *not* using. |

## Root cause
The service wrapper was changed to `exec` `/usr/bin/python3-lab`, which does not
exist on this machine, so the process died at startup and the port never opened.

## Fix
Point the wrapper back at the interpreter that is actually installed, then start
the service:

```bash
SVC=~/.breakfix-progress/state/s0-00-smoke/service
sed -i 's|/usr/bin/python3-lab|/usr/bin/python3|' "$SVC/run.sh"
( nohup bash "$SVC/run.sh" 18099 >>"$SVC/log" 2>&1 & echo $! > "$SVC/pid" )
```

Fixing the wrapper is the fix; starting a server by hand is not. The check stops
the service and starts it again through the wrapper for exactly that reason — a
process you started by hand dies with your shell and does not come back after a
reboot.

## Verification
`curl -i http://127.0.0.1:18099/` returns 200 with the status page body, and it
still returns 200 after the service has been stopped and started through the
wrapper. `ss -ltnp` shows the expected process owning the port.

## Prevention
- A listener check on the port, on a timer, alerting on the *state change* — the
  fault was visible as a closed port within seconds of the service dying.
- Have whatever starts the service refuse to start with a missing interpreter
  rather than failing silently into a log nobody reads: `test -x` the
  interpreter in the wrapper, or let a supervisor report the failed start.
- The real version of this is a broken `ExecStart` in a unit file, where
  `systemctl status` says `203/EXEC` and the fix is the same shape. A config
  test before reload catches it: `systemd-analyze verify` on the unit.

## What I did not know before this
"Connection refused" and "timed out" are different diagnoses, and the
distinction is free: refused means nothing is listening, so stop looking at the
application and look at whether the process is alive.
