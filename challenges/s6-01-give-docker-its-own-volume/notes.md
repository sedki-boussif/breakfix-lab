# s6-01 — author notes

**Why this mission and not the watchdog.** It was chosen over s6-04 because the
watchdog pattern — seven checks on a timer, alert on state change, recovery
message — already exists in production in the private application this lab
stands in for. Storage does not: adding a disk, building a volume group, moving
a live data directory and growing a filesystem under a running service is a
genuine gap, and a reversible one to practise.

**Why `/var/lib/docker` specifically.** It is the directory that actually fills
root volumes: images, build cache and container layers, growing without anyone
deciding to grow them. Moving it is the single most useful piece of storage work
on a machine like this, and it exercises every part of the LVM stack in one go.

**Why by UUID and not by device name.** `/dev/sdb1` is an artefact of
enumeration order, not an identity. A hypervisor that reorders devices, or a
disk added later, renames it — and an `/etc/fstab` entry by device name then
mounts the wrong thing or nothing at all. That is s5-07's failure mode arriving
by accident rather than by mistake, which is why the check asserts UUID
specifically.

**Why the copy needs `-H`.** Docker's `overlay2` store is built from hard links;
a copy that does not preserve them inflates the directory substantially and can
leave image layers subtly wrong. `rsync -aHAX --numeric-ids` is the incantation,
and knowing *why* each flag is there is most of the value.

**Why extend live.** Because it works, and almost nobody believes it until they
have done it. `lvextend` plus `resize2fs` on a mounted ext4 filesystem grows it
with the applications serving — and demonstrating that once is what makes
capacity planning a routine operation rather than a maintenance window.

**The trap.** Mounting by device name. Everything works, `df` looks right, the
check's other assertions pass, and the next time the hypervisor reorders a
device the machine does not boot. The check asserts the `fstab` entry is by
UUID for exactly this reason, and it checks across a real reboot because that is
the only honest test of a mount.

A second trap: deleting the old `/var/lib/docker` before verifying the new one.
If the copy was wrong, the images are gone — and the brief says to verify first,
in order.

**`PROVEN=unproven`, and it cannot be otherwise.** It needs a second physical
disk, real LVM, a real reboot, and a real Docker data directory. Every part of
that is outside what a container can honestly exercise, and by the testing
policy it is not something to attempt on a development machine.
