# s6-01 — Give Docker its own volume

## The goal
Move `/var/lib/docker` onto an LVM logical volume on the second disk, mount it
by UUID, and then grow it with everything still serving.

## What I did

```bash
# 1. Identify the disk. Twice.
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT      # /dev/sdb, 10G, no FSTYPE, no MOUNTPOINT

# 2. The LVM stack, verifying each layer before building the next.
sudo pvcreate /dev/sdb              && sudo pvs
sudo vgcreate dockervg /dev/sdb     && sudo vgs
sudo lvcreate -l 60%VG -n dockerlv dockervg && sudo lvs
sudo mkfs.ext4 -L dockerlv /dev/dockervg/dockerlv

# 3. Move the data, with Docker stopped.
sudo systemctl stop docker docker.socket
sudo mkdir -p /mnt/dockernew
sudo mount /dev/dockervg/dockerlv /mnt/dockernew
sudo rsync -aHAX --numeric-ids /var/lib/docker/ /mnt/dockernew/
sudo umount /mnt/dockernew

# 4. Mount by UUID, never by device name.
UUID=$(sudo blkid -s UUID -o value /dev/dockervg/dockerlv)
echo "UUID=$UUID /var/lib/docker ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mv /var/lib/docker /var/lib/docker.old
sudo mkdir /var/lib/docker
sudo mount -a                       # must be silent
sudo systemctl start docker

# 5. Verify BEFORE deleting the old copy.
docker images                       # everything that was there before
findmnt --target /var/lib/docker
for u in <the three app URLs>; do curl -fsS -o /dev/null -w "$u %{http_code}\n" "$u"; done
sudo rm -rf /var/lib/docker.old
```

Then arm, extend live, reboot:

```bash
lab check s6-01-give-docker-its-own-volume --arm

# the live extend, with a load loop running in another terminal
while :; do curl -s -o /dev/null -w '%{http_code} ' http://127.0.0.1:8080/api/health/; sleep 1; done

sudo lvextend -l +100%FREE /dev/dockervg/dockerlv
sudo resize2fs /dev/dockervg/dockerlv
df -h /var/lib/docker               # grew, with the loop still printing 200s

sudo reboot
lab check s6-01-give-docker-its-own-volume
```

## Measurements
Record yours. Mine: logical volume 6.0G → 10.0G, `df` 5.9G → 9.8G, and the
curl loop printed an unbroken run of 200s across the `lvextend` and `resize2fs`
— **zero failed requests**. That is the number the mission exists to produce.

## Why each flag in the copy
`rsync -aHAX --numeric-ids`:

- **`-H` is the one that matters.** Docker's `overlay2` store is built from hard
  links. Without it the copy inflates substantially and image layers can end up
  subtly wrong.
- `-A` and `-X` carry ACLs and extended attributes, which overlay2 and SELinux
  labelling use.
- `--numeric-ids` avoids remapping ownership through name lookups that may
  resolve differently inside the new tree.

## Why by UUID
`/dev/sdb1` is an artefact of enumeration order, not an identity. Add a disk,
or let the hypervisor reorder its controllers, and that name points somewhere
else — at which point an `fstab` entry by device name either mounts the wrong
filesystem or fails and takes the boot with it. That is exactly s5-07, arriving
by accident instead of by typo.

For an LVM volume the device-mapper path (`/dev/dockervg/dockerlv`) is also
stable, and would be a defensible choice. UUID is stable regardless of the
volume group's name, so it survives a rename as well.

## Verification
Across a real reboot: `/var/lib/docker` is a separate mount on an LVM logical
volume, `/etc/fstab` mounts it by UUID, `mount -a` is clean, the volume is
larger than when armed, Docker is running with its images intact, and all three
applications answer.

## What I got wrong first
Deleted `/var/lib/docker.old` before checking `docker images`. Nothing was lost
— the copy was good — but I had no way to know that at the time, and if the
copy had flattened the hard links I would have had no way back. Verify, then
delete, in that order; the brief says so and I did it anyway.

## What I did not know before this
That ext4 grows while mounted, so `lvextend` plus `resize2fs` is a zero-downtime
operation on a live service — which turns capacity management from a maintenance
window into a two-command routine. And how much of Docker's store is hard links,
and therefore how much a naive `cp -r` would have cost.
