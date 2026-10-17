Two facts in the alerts are doing all the work: the outage began four minutes after a reboot, and only one of the three apps is affected. Ask why the other two came back.
The apps are not all run the same way. Find out how nurse is supposed to start at boot, and compare it with how stages — which survived — is configured to start.
For a compose stack, what brings containers back after the daemon or the machine restarts is the per-service restart policy. `docker inspect -f '{{.HostConfig.RestartPolicy.Name}}'` on each container says what each one will do.
The nurse services have no restart policy, so nothing ever starts them again. Starting them by hand now will fix the symptom and change nothing about the next reboot.
Set a restart policy that survives both a daemon restart and a reboot — `unless-stopped` — in the compose file rather than on the running container, so it is still true after the next `up`. Then prove it: reboot, and do not touch anything.
The check compares when the container started against when the machine booted. A container you started by hand after the reboot will answer 200 and still fail, because it did not come up with the machine.
