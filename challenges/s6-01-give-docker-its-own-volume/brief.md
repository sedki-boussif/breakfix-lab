**The goal.** Move `/var/lib/docker` onto storage of its own, built on LVM, so
that images and container layers cannot fill the root filesystem — and then grow
it while everything keeps running.

You attached a second blank disk when you built this VM (SETUP.md §2). This is
what it is for. `lsblk` should show it with no partitions and no filesystem.

**The work, in order:**

1. **Build the stack.** Physical volume on the second disk, volume group, and a
   logical volume using **about 60% of the group** — leaving room to extend,
   which is the point of step 5.
2. **Make a filesystem** on the logical volume.
3. **Move the data.** Stop Docker, copy `/var/lib/docker` across preserving
   everything (`rsync -aHAX --numeric-ids`, or `cp -a`), mount the new volume at
   `/var/lib/docker`, start Docker. The old copy stays until you have verified
   the new one, then goes.
4. **Mount it by UUID** in `/etc/fstab`, not by device name. Device names move;
   `/dev/sdb1` today is `/dev/sdc1` after the hypervisor reorders something, and
   that is s5-07's failure mode arriving by accident.
5. **Then extend it live** — `lvextend` plus `resize2fs` — with the applications
   serving the whole time. No downtime, no unmount.

**The standard this will be checked against:**

- `/var/lib/docker` is a mount of its own, on an LVM logical volume.
- `/etc/fstab` mounts it **by UUID**.
- It **survives a reboot** — checked across a real one, in two phases.
- The logical volume is **larger than it was** when you armed the check.
- All three applications answer, and the report records that they stayed up
  during the extend.

**This is a two-phase check.** Build the stack and move the data, then
`lab check s6-01-give-docker-its-own-volume --arm` to record the starting size,
then extend it and reboot, then run the check without `--arm`.

Read the whole brief before you start step 3. Moving a running Docker's data
directory is the step where this goes wrong, and the order matters.
