Both of the clerk's observations are true at once: there is free space, and writes really do fail with ENOSPC. So the resource that has run out is not the one `df` reports by default.
A filesystem has two finite resources. `df -h` reports one of them. `df -i` reports the other, and on the spool volume it tells a very different story.
Inodes are exhausted: every file, however small, consumes one, and the count is fixed when the filesystem is created. 3% of the bytes are used and 100% of the inodes are.
Find where they went: `sudo find /srv/lab-scratch/spool -xdev -type f | wc -l`, and `sudo find /srv/lab-scratch/spool -xdev -type d -printf '%h\n' | sort | uniq -c | sort -rn | head` to see which directory holds them.
Delete the files that consumed the inodes and `df -i` recovers immediately. Adding space would not have helped: the inode count is set at format time and does not grow with the device.
If this were the real thing, the next question is what wrote them, because a filesystem formatted with that many inodes for that much space was sized for exactly this workload and something changed.
