# s9-04 — The flapping service

## Symptom
Users of the leave app are logged out at random, mid-task. The service is up
every time anyone checks, and nothing obvious is in the logs. It was dismissed
as "possibly a browser thing".

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl is-active leaves` | active | Which is what the previous investigation found, twice. Status is a snapshot; this fault lives in history |
| 2 | `systemctl show -p NRestarts --value leaves` | **37** | The answer. A service nobody has deployed in a week has restarted thirty-seven times |
| 3 | `systemctl status leaves` | `active (running) since … 2min ago` | Confirms it: up, and up for two minutes |
| 4 | `journalctl -u leaves --since '1 hour ago' \| grep -c Started` | Many | The cadence — roughly every two minutes |
| 5 | `journalctl -u leaves --since '1 hour ago' \| grep -B3 Started \| head -20` | `Main process exited, code=killed, signal=KILL` | Not a crash: something is killing it |
| 6 | `systemctl list-timers --all` | `lab-s9-04-flap.timer`, "Session cache maintenance", every 110s | The killer, under a name that sounds like it belongs |
| 7 | `systemctl cat lab-s9-04-flap.service` | `kill -9` the main PID of `leaves` | Confirmed |

**Dead end worth recording.** Looking in the application's own logs for an
error. There is none — the process is killed from outside, so it has no
opportunity to log anything. "Nothing in the logs" was accurate and was being
read as "nothing is wrong".

## Root cause
A timer was killing the leave service's main process every 110 seconds, and
`Restart=on-failure` brought it straight back. Sessions live in process memory,
so every restart logged everyone out. The restart policy — good practice — is
what made the fault invisible.

## Fix
```bash
sudo systemctl disable --now lab-s9-04-flap.timer
sudo rm /etc/systemd/system/lab-s9-04-flap.{timer,service}
sudo systemctl daemon-reload
sudo systemctl reset-failed leaves
sudo systemctl restart leaves

# then watch the number that matters
systemctl show -p NRestarts --value leaves; sleep 300
systemctl show -p NRestarts --value leaves    # must be the same
```

Not "restart it and see": restarting is what has been happening thirty-seven
times. The test is that the counter **stops moving**.

## Verification
The current main process has been up longer than five minutes, the restart
counter does not move across a three-minute window, and nothing is scheduled
against the service any more.

## Prevention
- **Alert on `NRestarts`.** It is the most under-used number in systemd: a
  service that has restarted more than N times in an hour is in an outage no
  matter what its current state says.
- **Monitor state transitions, not state.** Every liveness probe passed
  throughout this incident.
- **Move sessions out of process memory** — to the database or a cache. That
  makes a restart invisible to users, which is good *provided* you also alert on
  the restarts; otherwise it hides the fault more thoroughly than the restart
  policy did.
- **Audit scheduled units after any incident.** `systemctl list-timers --all`
  and the cron directories. A plausible name is not provenance, and this one
  looked like infrastructure.

## What I did not know before this
That `NRestarts` exists as a queryable property, and that it answers "is this
service healthy or merely currently up" in one command. And that a restart
policy is simultaneously the thing that keeps a service available and the thing
that hides why it is not.
