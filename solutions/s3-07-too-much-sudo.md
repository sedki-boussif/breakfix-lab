# s3-07 — A developer has too much sudo

## Symptom
None. Nothing is failing. An access review found that `dev1` holds
`ALL=(ALL) NOPASSWD: ALL` against a stated business need of "restart the web
server after a front-end deploy", and requires the grant reduced and evidenced.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `sudo -l -U dev1` | `(ALL) NOPASSWD: ALL` | The authoritative answer. sudo's own view accounts for drop-in files, group membership and defaults together, which reading files one at a time does not |
| 2 | `sudo grep -r dev1 /etc/sudoers /etc/sudoers.d/` | `/etc/sudoers.d/dev1` holds the grant | Locates it. Ruled out `/etc/sudoers` itself and a stray `%wheel` rule |
| 3 | `id dev1` | Not in the `sudo` group | Important: if it had been, removing the drop-in would have left the distribution's `%sudo ALL=(ALL:ALL) ALL` in place and the account would still have had everything |
| 4 | `sudo last -n 20 dev1`, `sudo grep dev1 /var/log/auth.log` | No sudo use recorded | The grant has not been exercised. It is still a finding, and it tells you nobody depends on the breadth |
| 5 | `systemctl cat nginx \| head -3` and `command -v systemctl` | `/usr/bin/systemctl` | The exact path and command the narrow grant must name |

## Root cause
A drop-in file granting unrestricted passwordless sudo, created to satisfy a
legitimate need for one command. Not a malfunction — a standing over-grant.

## Fix
```bash
sudo visudo -f /etc/sudoers.d/dev1
```

with exactly:

```
dev1 ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
```

then `sudo visudo -c` to validate every file, and `sudo -l -U dev1` to confirm
one line.

Use `visudo`, not an editor: it validates before saving, and a malformed sudoers
file removes sudo for everyone including you.

Why the arguments are named: sudo matches the command line literally. A grant of
`/usr/bin/systemctl` with no arguments permits `systemctl stop postgresql`,
`systemctl mask ssh`, and starting a unit the account wrote itself — which is a
root shell by another route. `/usr/bin/systemctl *` is the same hole with a
wildcard in it. The whole value of the narrow grant is in the arguments.

**Write the path sudo resolves.** sudo ignores the invoking user's `PATH` and
uses `secure_path` from `/etc/sudoers`. If `systemctl` exists at more than one
location on that path, the grant must name the one sudo finds first, or every
invocation is denied and the narrow grant looks broken. Confirm with
`sudo -l -U dev1` and then by actually running the command as the account — not
by reading the file you just wrote.

Keeping `NOPASSWD` is a deliberate choice, not an oversight: the command runs
from a deploy script that cannot answer a prompt, and the grant is now one
harmless command. Removing `NOPASSWD` on a grant of `ALL` would have been
rearranging deck chairs.

## Verification
`sudo -l -U dev1` lists exactly one permitted command. As `dev1`:
`sudo -n systemctl restart nginx` succeeds; `sudo -n systemctl restart
postgresql` is refused; `sudo -n /bin/bash` is refused. nginx is running
afterwards. That is the evidence the review asked for — both halves, the grant
and its limit.

## Prevention
- **`sudo -l -U <user>` for every privileged account, on a schedule.** It is the
  only view that composes files, groups and defaults, and it is one command.
- **Grant to a task, not to a person.** A one-line wrapper script owned by root,
  with the grant naming the wrapper, is easier to read and to audit than a
  `systemctl` invocation with arguments.
- **Keep grants in `/etc/sudoers.d/<name>` with a comment** saying who asked, for
  what, and when it should be reviewed. An undated grant is permanent.
- **Watch the `sudo` group as closely as the drop-ins.** Membership is the grant
  people forget, because it is invisible from `/etc/sudoers.d`.

## What I did not know before this
How literally sudo matches arguments, and therefore how much a grant of a bare
binary path really gives away — `systemctl` alone is effectively root, because it
can start a unit the account controls. Also that `runuser -u <user> -- sudo -n`
is a clean way to test someone else's grant without logging in as them.
