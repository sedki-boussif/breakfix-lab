Emergency mode means systemd could not reach its basic target, and by far the most common reason is a mount it was told to make and could not. You are at a root prompt with a read-only or partly-mounted filesystem, so start by reading, not changing.
`journalctl -xb` scrolled to the failures, or `systemctl --failed`, names the unit that gave up. A failed `.mount` unit's name is the mount point with the slashes escaped.
`cat /etc/fstab` and compare each entry against reality: `blkid` and `lsblk -o NAME,UUID,FSTYPE,MOUNTPOINT` list what the machine actually has. One entry names a UUID that does not exist on this machine.
You may need the root filesystem writable before you can edit anything: `mount -o remount,rw /`.
Fix the entry — correct the UUID, or remove the line if the device is genuinely gone — and verify with `mount -a`, which must return silently before you trust a reboot. A `nofail` option would also let the machine boot, and is the right answer for a device that is legitimately optional.
Then reboot and watch it come up unaided. The check is in two phases for that reason: arm it before the reboot, run it again afterwards.
