# s3-06 — author notes

**What the fault really is.** The nurse compose services lose their restart
policy — `restart: "no"` via an override, which is also what you get by simply
omitting the key. Everything works until the Docker daemon or the machine
restarts, after which the containers stay exited and nothing notices except the
watchdog. In systemd mode, the equivalent is `systemctl disable`: active now,
absent after boot.

**Why it is realistic.** This is the single most common difference between "it
works" and "it is deployed". It is invisible for however long the machine stays
up — weeks, usually — and surfaces during an unattended-upgrades reboot at three
in the morning, which is also when nobody is reading alerts.

**Why the reporter is a monitoring system.** No interpretation at all: four
timestamps, two endpoints, a status code of 000, and one unrelated-looking system
message about a reboot. Everything needed to solve it is in those lines — the
reboot four minutes earlier, and the fact that two of three apps are unaffected —
and none of it is pointed out. Reading raw alerts for the two facts that matter is
a different skill from reading a user's prose, which is why this brief has no
prose.

**The trap.** Starting the containers by hand, which makes every endpoint answer
200 immediately and leaves the next reboot exactly as broken. A variant is
`docker update --restart unless-stopped` on the running container, which fixes
this machine and is lost on the next `docker compose up`, since the compose file
is still authoritative.

`check.sh` is two-phase for this reason. `--arm` records the boot id and the
current time; the post-reboot run asserts the app answers **and** that the boot
id has changed **and** that the container's start time is within a few minutes of
the machine's boot time. A hand-started container fails the last of those.

**Level 2 and a reboot.** The cause is one configuration key, but proving the fix
means a real reboot — the only honest test of "it survives a reboot" is a reboot.
The brief says so plainly, because a challenge that reboots your VM without
warning is a trick, not a lesson.
