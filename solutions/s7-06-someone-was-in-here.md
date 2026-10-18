# s7-06 — Someone was in here

## Symptom
None, locally. An abuse notice from the hosting provider reporting sustained
outbound connections since 02:40 UTC four days ago. The applications are
healthy, nothing failed, and none of the machine's own monitoring noticed.

## Investigation

Enumeration, not diagnosis. There is no symptom to work backwards from, so the
method is to walk identity, access, network and persistence in that order.

| # | Command | What it showed |
|---|---------|----------------|
| 1 | `awk -F: '$3>=1000 && $3<65534 {print $1, $7}' /etc/passwd` | An account `svc-backup`, uid 1001, shell `/bin/bash`. Not mine |
| 2 | `sudo lastlog -u svc-backup`, `sudo last svc-backup` | Logins, from an address I do not recognise |
| 3 | `sudo cat /home/svc-backup/.ssh/authorized_keys` | One ed25519 key, comment `sync@maintenance-node` |
| 4 | `sudo ss -ltnp` | Something on 127.0.0.1:47113, not in `EXPECTED_PORTS` |
| 5 | `sudo ls -l /proc/<pid>/exe` | `/usr/bin/python3` — the process calls itself `[kworker/u8:2-events]` to look like a kernel thread. Kernel threads have no `exe` link at all, which is the tell |
| 6 | `ls -la /etc/cron.d/` | `lab-svc-backup-sync`, "Node synchronisation helper" |
| 7 | `cat /etc/cron.d/lab-svc-backup-sync` | Every two minutes, re-adds that key to that account's `authorized_keys` |
| 8 | `sudo grep -rn svc-backup /etc/cron* /etc/systemd /var/spool/cron` | Nothing else |
| 9 | after cleanup, wait and re-check | Nothing returns |

**The dead end that teaches the lesson.** I removed the key, the account and the
process first — the three visible things — and the key was back within two
minutes. **Find the persistence before you clean anything**, because otherwise
you are racing a cron job and you will not notice you lost.

## Root cause
Four traces of one intrusion:

1. **`svc-backup`**, uid 1001, with a login shell — the account.
2. **An unknown ed25519 key** in its `authorized_keys` — the access.
3. **A cron entry in `/etc/cron.d`** re-adding that key every two minutes — the
   persistence, and the reason removing the key alone achieved nothing.
4. **A python process on 127.0.0.1:47113** with `argv[0]` set to look like a
   kernel thread — what the provider noticed.

## Fix
In this order, which is the only order that works:

```bash
# 1. Persistence first.
sudo rm -f /etc/cron.d/lab-svc-backup-sync

# 2. The running process.
sudo kill "$(sudo ss -ltnpH 'sport = :47113' | grep -oP 'pid=\K[0-9]+')"

# 3. The access and the account.
sudo userdel -r svc-backup

# 4. Verify nothing comes back. Wait longer than the persistence interval.
sleep 180
getent passwd svc-backup; sudo ss -ltnp | grep 47113
sudo find /home /root -name 'authorized_keys*' -exec grep -l 'maintenance-node' {} +
```

## Verification
All four absent, and still absent after waiting out the persistence window —
which is the only assertion that distinguishes a cleanup from a pause. Then the
wider sweep: no other account outside `EXPECTED_USERS`, no port outside
`EXPECTED_PORTS`, root the only uid 0.

## What I cannot conclude, and should not pretend to
This machine cannot establish its own integrity. I found four things; I cannot
prove there was not a fifth. On a real host the honest next step after this
cleanup is **rebuild from known-good sources** — which is what s8-02 exists to
practise — and treat every credential this machine held as compromised:
database passwords, the restic password, any key in any `authorized_keys`, any
token in any `.env`.

## Prevention
- **A baseline, and something that compares against it.** `EXPECTED_PORTS` and
  `EXPECTED_USERS` in `lab.conf` are that baseline, and `health_check` compares
  against them. An unexpected listener should alert in minutes, not arrive by
  email in four days.
- **Watch for account creation and `authorized_keys` changes.** A file watch on
  every `authorized_keys`, plus an alert on `useradd`, catches traces 1 and 2 at
  the moment they happen.
- **Egress monitoring, or at least egress *awareness*.** The provider noticed
  outbound traffic that this machine's own instruments did not look at.
- **Never trust `comm`.** `/proc/<pid>/exe` and `cmdline` are the facts, and a
  real kernel thread has no `exe` link — that single check identifies this whole
  class of disguise.
- **Find out how they got in.** None of the above answers that, and the four
  traces are the consequence rather than the cause.

## What I did not know before this
That a kernel thread has no `/proc/<pid>/exe` symlink at all, so a userspace
process wearing a `[bracketed]` name is identifiable in one command. And the
ordering rule — persistence before artefacts — which is obvious in hindsight and
was not obvious while the key kept reappearing.
