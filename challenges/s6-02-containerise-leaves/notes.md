# s6-02 — author notes

**Why this is a mission and not a setup step.** The original plan had `SETUP.md`
containerise both Django apps. Neither public repository ships a Dockerfile —
`leaves` and `nurse` both describe gunicorn deployments — so setup would have
had to write one untested, in the middle of a first VM run, and the reader
would never see it as work. Containerising an application is worth doing as a
graded exercise with a check on it. s6-07 extends the same reasoning to the
second repository.

**Why the standard lives in `lib/compose.sh`.** s6-02 and s6-07 are the same
exercise against different applications, held to the same seven properties.
A standard written out twice is two standards within a month, and the second
app is exactly where the drift would appear. Same argument as `lib/accept.sh`
and `health_check`.

**Why the checks read `docker compose config --format json` through jq.**
Grepping the YAML would be shorter and wrong. Compose accepts short and long
form for ports and volumes, `extends`, and override files, and the normalised
output is what compose actually believes — one shape to write filters against
instead of four spellings to match. The one thing deliberately read from the
raw file is secrets: `config` resolves `${VARS}`, so a password supplied
properly from the env file appears in the JSON too, and its absence there would
prove nothing at all. That distinction is the whole reason the secrets
assertion looks different from its neighbours.

**Why the volume assertion has four branches.** Because "there is a volume" and
"the data survives" are different claims, and three of the four ways to get
this wrong look fine from the outside:

- a **bind mount** works until the host path moves, and puts database files
  where a backup of `/opt` will copy them half-written;
- an **anonymous volume** — mounted by name but never declared top-level —
  actually does survive `down`, and is then unfindable among a dozen
  hex-named volumes, which is worse than losing it cleanly;
- **no mount at all** puts the data in the container's writable layer, where
  it survives `restart` and dies with `down`, so the mistake is invisible
  until the first real deploy.

Each gets its own message naming which of those it is.

**Why `depends_on` gets its own assertion separate from the healthcheck.** They
fail together and are fixed separately. `depends_on` without a condition waits
for *started*, and a started PostgreSQL is one that exists and is still
replaying WAL — so the app connects, fails, and `restart: unless-stopped`
brings it back working. The result is a stack that fails on the first attempt
after every reboot and succeeds on the retry, which nobody investigates because
it always comes good. Both halves are needed: the condition is meaningless
without a healthcheck to evaluate.

**Why the port is asserted twice — presence and interface.** `"8081:8081"`
publishes on every interface, and Docker inserts its own iptables rules ahead of
ufw's, so the port is reachable from the network while `ufw status` still
reports it closed. That is s4-04, and it is far easier to cause here than to
notice. The second assertion names s4-04 explicitly so the connection is made
at the point of the mistake rather than weeks later.

**The trap.** Leaving the systemd unit enabled. Everything works — the
container serves, the check's HTTP assertion passes, nothing complains — and at
the next boot the unit and the container race for 8081. Whichever loses fails
in a way that looks like neither this challenge nor s5-06, which is what it
actually is. `stop` and `disable` are different verbs and the check asserts
both.

A second trap, quieter: restoring the dump into the host database instead of
the container's. Port 5432 on the host still answers, `psql` connects happily,
and the restore succeeds into the database being migrated away from. The
container comes up empty, and the obvious conclusion — that the restore failed
— is wrong. The hints name it.

**Why "holds data at all" is asserted before "survives destruction".** A stack
that comes back empty from empty is perfectly consistent and proves nothing: 0
equals 0 and the survival assertion passes. That is a vacuous pass of exactly
the kind `assert_absent`'s controls exist to prevent, arrived at from the other
direction, so the row count is required to be above zero before the comparison
is believed. The check also refuses to run `down -v` anywhere, which is the
difference between a restart and a data loss.

**`PROVEN=mock-compose`.** Verified against nine compose projects through a
`docker compose config` shim that normalises real YAML the way compose does —
a correct project (fifteen assertions, all passing), a bind mount, no mount, an
undeclared volume, publishing on all interfaces, the wrong port, a missing
healthcheck with a conditionless `depends_on`, a password written into
`compose.yaml`, and a database that comes back empty. What is not exercised is
a real Docker build of a real Django application, which is why this is mock.
