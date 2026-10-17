# s5-07 — The VM boots to emergency mode

## Symptom
After a patching reboot the machine does not come back. No ping, no SSH. The
hypervisor console shows a root prompt and a message about emergency mode and
pressing Enter for maintenance. All three applications are down with it. The only
change beforehand was "tidying up the mount table".

## Investigation

All of this is done at the console, as root, with no network.

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl --failed` | `srv-lab\x2dscratch-archive.mount` failed | Names the unit. A failed `.mount` unit is a dependency of `local-fs.target`, which is why the boot stopped |
| 2 | `journalctl -xb \| tail -40` | `Dependency failed for Local File Systems`, then `Timed out waiting for device /dev/disk/by-uuid/1111…` | Confirms the chain, and that the device never appeared rather than failing to mount |
| 3 | `cat /etc/fstab` | An entry `UUID=11111111-2222-3333-4444-555555555555 /srv/lab-scratch/archive ext4 defaults 0 2` | The suspect |
| 4 | `blkid` and `lsblk -o NAME,UUID,FSTYPE,MOUNTPOINT` | No such UUID on the machine | Confirms it. The entry names a device that does not exist |
| 5 | `mount -o remount,rw /` | Root is writable | Needed before anything can be edited; a read-only root is the usual first obstacle |

**Dead end worth recording.** Looking for disk failure — `dmesg | grep -i sd`,
`smartctl` — which is a reasonable response to "a device did not appear" and
takes a few minutes to eliminate. The disks are fine; the UUID was never right.

## Root cause
An `/etc/fstab` entry named a UUID that does not exist on the machine, with no
`nofail`. systemd generated a mount unit from it, the unit could not be
satisfied, `local-fs.target` failed, and the boot stopped in emergency mode.

The edit had been harmless for weeks. `fstab` is only consulted at boot and by
`mount -a`, so the fault was created long before it was triggered — which is why
the reporter's "I only tidied up the mount table" is both true and the whole
answer.

## Fix
At the console:

```bash
mount -o remount,rw /
vi /etc/fstab            # correct the UUID, or remove the line
mount -a                 # MUST return silently before you trust a reboot
systemctl daemon-reload
reboot
```

Three legitimate fixes, in order of preference:

1. **Correct the UUID** if the device exists and was mistyped. Take it from
   `blkid`, copy-pasted, never retyped.
2. **Remove the line** if the device is genuinely gone.
3. **Add `nofail`** (and `x-systemd.device-timeout=10s`) if the device is
   genuinely optional — a removable disk or a network mount that may be absent.
   This is right for optional devices and wrong as a reflex: on a device that is
   supposed to be there it converts a loud failure into a filesystem that is
   silently missing, which is how data gets written to the wrong place.

`mount -a` is the test that matters. It does exactly what the boot will do, and a
clean run is the difference between a confident reboot and a second outage.

## Verification
The machine boots unaided to a working state: the boot id has changed, the
default target is active, emergency mode is not, `mount -a` is clean, no mount
unit is failed, no fstab entry names a device that is not there, and all three
applications answer. The check is two-phase — armed before the reboot, run after
— because the only honest test of "it boots" is a boot.

## Prevention
- **`mount -a` after every fstab edit, immediately.** It costs one second and it
  is the entire prevention. Nearly every instance of this fault is an edit nobody
  tested because the machine was already up.
- **`nofail` on everything genuinely optional**, so an absent optional device
  cannot stop a boot.
- **Reboot deliberately after changing anything in the boot path**, at a time you
  choose, rather than discovering it during patching at 02:40.
- **Keep the console reachable and know how to open it** before you need it. The
  first half of this incident is recovery and the second half is the fix, and the
  recovery is impossible without the console.
- **Copy UUIDs, never type them.** `blkid -s UUID -o value /dev/sdb1` into the
  file.

## What I did not know before this
That a *non-root* mount failing is enough to stop the boot entirely — `defaults`
makes the mount a hard dependency of `local-fs.target`, so an optional-looking
extra disk takes the whole machine down. And that the failed unit's name is the
mount point with slashes escaped as `\x2d` and `-`, which is how to find it in
`systemctl --failed` when the name looks like line noise.
