# s8-01 — Build the server from nothing

## The goal
From a bare Ubuntu 24.04 image to a machine that passes the full acceptance
suite: three applications over HTTPS, exactly the expected ports, key-only SSH
behind a narrow firewall, backups that restore to the right data, monitoring
that fires and recovers — and all of it still true after a reboot.

## The order that works

The order below is not the only one, but every departure from it costs time in
a specific, predictable way, noted where it applies.

```bash
# 0. Start the clock, and the lab's own record of it.
lab start s8-01-build-from-nothing

# 1. The account and the keys. Two terminals from here on: one to build with,
#    one to prove with. Never harden SSH from a session you cannot replace.
sudo adduser --disabled-password --gecos '' <admin>
sudo usermod -aG sudo <admin>
sudo install -d -m 700 -o <admin> -g <admin> /home/<admin>/.ssh
sudo tee /home/<admin>/.ssh/authorized_keys <<<'<your public key>'
sudo chmod 600 /home/<admin>/.ssh/authorized_keys
sudo chown <admin>:<admin> /home/<admin>/.ssh/authorized_keys
#    Second terminal, BEFORE the next step:
ssh <admin>@<the VM>            # must work with the key, with no password

# 2. Harden SSH, then ask sshd what it will actually do.
sudo tee /etc/ssh/sshd_config.d/99-lab.conf <<'CONF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
CONF
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication'

# 3. The firewall, before anything is listening. SSH first, every time.
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose

# 4. Docker, enabled at boot — the step a hand-built machine forgets.
#    Packages and repository per SETUP.md section 4; --now is not enable.
sudo systemctl enable --now docker

# 5. The three applications, per SETUP.md sections 5 to 7, bound to loopback
#    so nginx is the only thing the network can reach.
# 6. The data.
sudo bash lib/seed.sh

# 7. Host nginx with TLS last: it proxies to things that must already exist.
#    One certificate carrying all three names, per SETUP.md section 8.
openssl x509 -in /etc/nginx/tls/lab.crt -noout -ext subjectAltName
sudo nginx -t && sudo systemctl reload nginx

# 8. Backups AFTER the seed. This ordering is load-bearing — see below.
sudo systemctl enable --now lab-backup.timer
sudo systemctl start lab-backup.service          # one run now, so an archive exists
sudo systemctl enable --now lab-backup-watch.timer

# 9. Write down what you built, because the suite holds you to it.
ss -ltnH | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' '
awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd | tr '\n' ' '
#    into EXPECTED_PORTS, EXPECTED_USERS and LAB_ADMIN_USER in lab.conf

# 10. Arm, reboot, prove.
lab check s8-01-build-from-nothing --arm
sudo reboot
lab check s8-01-build-from-nothing
```

## Why the order is what it is

| Step | If you do it later | What it costs |
|---|---|---|
| Keys before hardening | Harden first, key second | You lock yourself out and need the hypervisor console. This is s4-06, by accident |
| Firewall before apps | Apps first | A window where something is listening unprotected, on a machine you cannot be sure nobody scanned |
| Loopback binds before Docker publishes | Publish to `0.0.0.0` | Docker writes its own iptables rules and ufw never sees the traffic. This is s4-04, by accident |
| nginx after the apps | nginx first | `nginx -t` passes and the proxy 502s, so you debug nginx for twenty minutes to discover the upstream was never started |
| Backups after the seed | Backup first, seed second | The suite's restore comparison fails, and the failure *reads* as a broken restore when it is a stale archive |
| `enable` as you go | `start` now, `enable` later | The reboot assertion fails, which is the single most common way this mission is failed |

## Verification
`lab check s8-01-build-from-nothing` is the verification, and it is the point of
the challenge rather than an afterthought. What it proves that building carefully
does not:

- **HTTPS per vhost by SNI** — one certificate covering three names, checked
  name by name, so a certificate issued for one of them fails.
- **The listening set in both directions** — a missing service and a stray
  development server are both failures.
- **A real restore** — the latest archive is restored and its row counts
  compared against the live database.
- **A full alert cycle** — the suite backdates the backup marker, requires an
  alert, restores it, and requires the alerting to go quiet.
- **A reboot** — a boot id that changed, which nothing can fake.

## Prevention
The number this mission produces is the input to everything in s8-02: the
measured time from bare image to green suite. Write it in the report. Then write
the runbook while the commands are still in your shell history —
`history | grep -v '^ *[0-9]* *lab '` is a better first draft than memory, and
s8-03 is the exercise that finds out whether that draft was any good.

The second thing worth keeping is the two lists. `EXPECTED_PORTS` and
`EXPECTED_USERS`, captured from the machine when it was in a state you were
willing to defend, are what turns every later health check from a formality into
an assertion.

## What I did not know before this
That `sshd -T` and `/etc/ssh/sshd_config` can disagree, and that a drop-in in
`sshd_config.d` is what usually settles it — so the only honest way to check SSH
hardening is to ask the daemon rather than to read the file. And that the
expensive failures in a rebuild are all ordering failures: every one of them is
a step that works perfectly and makes a later step fail somewhere else.
