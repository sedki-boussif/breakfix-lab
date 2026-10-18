# s2-04 — Rotate the app logs

## The goal
A logrotate rule for `$LEAVES_LOG`: daily, keep 7, compressed — and the
application still writing afterwards.

## The rule

```
# /etc/logrotate.d/leaves
/var/log/leaves/access.log {
    daily
    rotate 7
    compress
    delaycompress        # the newest rotation stays readable
    missingok            # do not complain before the file exists
    notifempty           # do not archive seven empty files
    create 0640 www-data adm
    sharedscripts
    postrotate
        systemctl kill -s USR1 leaves.service
    endscript
}
```

The alternative, if you would rather not depend on the application:

```
    copytruncate
    # and no create/postrotate: the file handle stays valid because the file
    # is never renamed, only copied and truncated in place.
```

## Checking it without waiting a day

```bash
sudo logrotate --debug /etc/logrotate.d/leaves      # parses, prints, does nothing
#   rotating pattern: /var/log/leaves/access.log  after 1 days (7 rotations)

sudo logrotate --debug /etc/logrotate.conf | grep leaves   # is it even included?

sudo logrotate --force --verbose /etc/logrotate.d/leaves   # actually rotate
ls -l /var/log/leaves/
curl -s -o /dev/null "$LEAVES_URL"                  # make it write
wc -c /var/log/leaves/access.log                    # must not still be 0
```

That last pair is the whole mission. If the log is still zero bytes after a
request, the rotation worked and the application did not notice.

## Why the fourth property is the hard one

A process holds an open **file**, not a filename. `logrotate` renames the file;
from the application's point of view nothing happened, and it keeps writing to
an inode that no longer has a name.

```bash
sudo ls -l /proc/"$(pgrep -f gunicorn | head -1)"/fd/
# ... 3 -> /var/log/leaves/access.log.1 (deleted)
```

That `(deleted)` is the whole problem in one line: the application is writing
somewhere nothing will ever read, and the space is not freed either. It is
`s5-03` — "deleted file held open" — arriving by appointment.

| Fix | How it works | What it costs |
|---|---|---|
| `postrotate` + `SIGUSR1` | the application closes and reopens its log files | needs the application to handle the signal; needs the right pid, which is why `systemctl kill -s USR1 <unit>` beats a pidfile |
| `copytruncate` | the file is copied aside and truncated in place, so the handle stays valid | anything written between the copy and the truncate is lost |

`systemctl kill -s USR1 leaves.service` is more reliable than
`kill -USR1 $(cat /run/leaves.pid)` because the unit always knows its main
process and the pidfile may not exist.

## Verification
`lab check s2-04-rotate-the-logs`, which forces a rotation, decompresses the
result rather than trusting the suffix, makes requests and watches the new file
grow, and scans `/proc/*/fd` for a process holding a deleted copy — planting
one first to prove the scan works.

## Prevention
Two habits come out of this:

- When you configure an application to write a log, write its rotation rule in
  the same sitting. A log with no rotation rule is a disk-full incident with a
  date on it, and `s5-01` is that incident.
- After any rotation change, force one and confirm the application is still
  writing. The rule being right and the rotation working are two different
  claims, and only the second one is visible from outside.

## What I did not know before this
That `delaycompress` means the newest rotation is deliberately left
uncompressed, so one rotation can never prove compression is configured — and
that forcing a second rotation immediately afterwards does nothing, because the
new log is empty and `notifempty` skips it. Two directives that are each
obviously sensible, interacting to make a correct configuration look broken.
