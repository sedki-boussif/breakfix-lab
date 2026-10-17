# s3-05 — author notes

**What the fault really is.** The uploads volume's host path is chowned to root
and its mode narrowed, so the api container — which runs as uid 10001 — gets
`EACCES` on write. The endpoint returns 500 with the errno and the path, which is
the application behaving well; the browser swallows it, which is why the report
is so poor.

**Why it is realistic.** This is what a careless restore or a backup script run
as root leaves behind: files come back with root ownership and nothing can write
to them any more. It also happens when a volume is recreated and the image's
`chown` in the Dockerfile only applies to the image's own copy of the directory,
not to a volume mounted over it.

**Why the reporter is vague.** Deliberately: most reports are this bad. There is
no timestamp worth having, no error text, no reproduction. The first move is not
investigation but *reproduction* — turning "it goes red" into a status code and a
message. The brief gives just enough to find the endpoint, and nothing else.

**The trap.** Two, both enforced:

1. **`chmod 777`.** The upload works instantly. It also grants write to every
   process on the host and every other container that mounts the volume, and
   whatever created a root-owned file here will do it again. `check.sh` refuses a
   world-writable uploads directory.
2. **Running the container as root** — adding `user: root`, or dropping the
   `USER appsvc` line. Writes succeed because everything succeeds.
   `check.sh` asserts the api is not running as uid 0.

**Level 2.** One cause, found with `ls -ld`, but it sits across a boundary — a
uid inside a container against ownership on the host — and both shortcuts are
security regressions rather than fixes.
