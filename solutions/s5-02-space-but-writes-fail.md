# s5-02 — Disk has space but writes fail

## Symptom
Writes to `/srv/lab-scratch/spool` fail with `No space left on device` while
`df -h` reports the filesystem 3% used. Reported as "the disk is full, please add
more disk".

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `sudo touch /srv/lab-scratch/spool/x` | `No space left on device` | Reproduces it. The error is real and is `ENOSPC`, not a permission problem |
| 2 | `df -h /srv/lab-scratch/spool` | 3% of bytes used | Confirms the reporter. Both of her observations are true |
| 3 | `df -i /srv/lab-scratch/spool` | **100% of inodes used** | The answer, second command in. A filesystem has two finite resources and `df` shows the other one by default |
| 4 | `sudo find /srv/lab-scratch/spool -xdev -type f \| wc -l` | ~2040 files | Where they went |
| 5 | `sudo find /srv/lab-scratch/spool -xdev -type f -printf '%h\n' \| sort \| uniq -c \| sort -rn \| head` | All under `incoming/.partial` | Names the directory, and the name says what it was: partial uploads never cleaned up |
| 6 | `sudo dumpe2fs -h /dev/loop0 \| grep -i inode` | Inode count fixed at format time | Explains why "add more disk" cannot work: growing the device does not add inodes to an existing ext4 filesystem |

**Dead end worth recording.** Looking for large files first. It is the right
reflex for `ENOSPC` and takes one command to eliminate — which also confirms this
is not s5-01.

## Root cause
The spool filesystem ran out of inodes. About two thousand empty files consumed
every inode in a table fixed when the filesystem was created, so every new file
failed with `ENOSPC` while 97% of the bytes were still free.

## Fix
```bash
sudo find /srv/lab-scratch/spool/incoming/.partial -xdev -type f -delete
df -i /srv/lab-scratch/spool
```

Why not add space: the inode count is set by `mkfs` and does not grow with the
device. Adding disk would have cost money, taken a maintenance window, and
changed nothing — which is why the requested remedy in the ticket had to be
refused rather than scheduled.

If the files are needed, the answer is a filesystem formatted for many small
files (`mkfs.ext4 -i 4096`, or a different filesystem), not a bigger one.

## Verification
`df -i` under 80%, and a write actually succeeds — the end state the clerk cares
about, which is not the same claim as a number having changed. The check proves
its own counting first by creating a known batch of files, requiring the detector
to see them, and removing them.

## Prevention
- **Monitor `df -i` alongside `df -h`.** Almost nobody does, and the failure is
  indistinguishable from a full disk in every application log.
- **Whatever writes `incoming/.partial` must clean up after itself**, including
  when it fails. A spool directory that only grows is a scheduled outage.
- **Size the filesystem for the workload at format time.** A volume for many
  small files needs `-i` set; the default assumes average files of 16 KB.

## What I did not know before this
`ENOSPC` means "no space left on device" for either resource, and the error text
cannot tell you which. `df -i` is the second command to run on any full-disk
report, and it takes a second.
