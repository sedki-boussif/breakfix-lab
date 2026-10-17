# s3-06 — It works until the server reboots

## Symptom
Both nurse endpoints went unreachable overnight and stayed down. No recovery
message. The other two applications reported nothing. A scheduled reboot for
unattended-upgrades completed four minutes before the first alert.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | — | The alerts themselves: outage begins after a reboot, and only one of three apps is affected | Ruled out the network, nginx, DNS and the host. Two apps came back; the question is why the third did not |
| 2 | `uptime -s` and the alert timestamps | The machine booted at 02:58, first alert 03:02 | Confirms the reboot is the trigger rather than a coincidence |
| 3 | `docker compose -p nurse ps -a` | Both containers `Exited (0)` | They were stopped cleanly by the daemon shutting down, and never started again. Not a crash |
| 4 | `docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' <nurse api>` | `no` | The answer |
| 5 | the same on a stages container | `unless-stopped` | Explains the difference between the apps, and tells you what the fix should look like |
| 6 | `journalctl -b -u docker \| head` | The daemon started normally and restarted the containers it was told to | Ruled out a Docker fault |

**Dead end worth recording.** `systemctl is-enabled docker` — reasonable, and it
is enabled. The daemon came back; it just had nothing to bring with it.

## Root cause
The nurse compose services had no restart policy, so neither container was
started again after the Docker daemon stopped and started across the reboot.

## Fix
In `/opt/nurse/compose.yaml`, on each long-running service:

```yaml
    restart: unless-stopped
```

then `docker compose up -d` to recreate the containers with the policy.

Why in the compose file rather than `docker update --restart unless-stopped` on
the running container: the live change works and is silently undone by the next
`docker compose up`, because the compose file is authoritative. A fix that the
next deploy reverts is a fault with a delay on it.

Why `unless-stopped` rather than `always`: `always` restarts a container you
deliberately stopped, including across a reboot, which makes maintenance
frustrating and hides deliberate downtime.

## Verification
The only honest verification is a reboot. `lab check s3-06-works-until-reboot
--arm` records the boot id, then `sudo reboot`, then run the check without
`--arm`: it asserts the boot id changed, both endpoints answer, the policy is
`unless-stopped`, and — the part that matters — the container's `StartedAt` is
within a few minutes of the machine's boot time, so it came up *with* the machine
rather than being started by hand afterwards.

## Prevention
- **Reboot on purpose, after every deployment.** This fault is invisible for as
  long as the machine stays up. A deliberate reboot at a time of your choosing
  converts a 3 a.m. outage into a two-minute check.
- **Make the acceptance suite include a reboot** — s8-01's does.
- **Alert on the absence of a recovery message.** Four alerts arrived and nothing
  escalated. A check that is still failing after two cycles is a different event
  from one that has just started failing; s6-04 is about exactly that.
- **Diff the deployments.** Two apps had a restart policy and one did not. A
  configuration that is inconsistent across three services deployed by the same
  person is worth a five-minute audit.

## What I did not know before this
`Exited (0)` is the giveaway: a crashed container exits non-zero, so a clean exit
code after a reboot means the daemon stopped it deliberately and nothing was
asked to start it again. And a restart policy set with `docker update` does not
survive `docker compose up`.
