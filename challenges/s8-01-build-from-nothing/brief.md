**The goal.** From a bare Ubuntu 24.04 image, build this machine: the account
you log in as, SSH that only accepts your key, a firewall, Docker, host nginx
with TLS, all three applications with their fake data, backups running on a
timer, and monitoring that alerts. Then reboot it and prove it all came back.

**Record the time.** Start the clock when the bare image first boots and stop
it when the check passes. Not because it is a race — because the number is the
only honest input to the recovery time objective you will be held to in s8-02,
and a rebuild time nobody measured is a guess wearing a promise's clothes.

**This is not a new build.** Every piece of it is something you have already
done once, and SETUP.md is the record of how. What is new is doing all of it in
one sitting, in an order you choose, against a suite that checks the whole
machine at once rather than one stage at a time.

**The work, in order — the order is yours to choose, but these are the
dependencies that will bite:**

1. **The account and the keys first**, and test logging in from your laptop in
   a second terminal *before* you turn password authentication off. Harden SSH
   from a session you already have open, and keep it open.
2. **The firewall before the applications**, so you never have a window where
   something is listening and unprotected. Open only what `EXPECTED_PORTS`
   lists.
3. **Docker, then the three applications**, then the seed data. `lib/seed.sh`
   does the data; the applications come up `compose` or `systemd` per
   `lab.conf`.
4. **Host nginx with TLS last**, because it proxies to things that have to
   exist first. Every vhost on the certificate, and plain HTTP redirected to
   HTTPS rather than left serving.
5. **Backups after the data**, and this order is load-bearing: the suite
   restores the latest archive and compares it against what is being served, so
   an archive taken before the seed will not match. Seed, then back up, then
   check.
6. **Monitoring that speaks.** The dead-man's-switch from s7-01, and the suite
   will make it fire on purpose and then require it to go quiet again.
7. **Then reboot**, and run the check.

**The standard this will be checked against** — the full acceptance suite, and
it is deliberately the whole machine:

- The three applications answer **over HTTPS**, each on its own vhost name,
  with a certificate that covers the name and has time left on it, and plain
  HTTP redirects.
- The listening set is **exactly** `EXPECTED_PORTS` — nothing extra, and
  nothing missing.
- Your admin account exists, has keys, and can escalate; SSH accepts keys only
  and refuses root; `ufw` is active and narrow; Docker is enabled at boot.
- **One backup has run and been restored** — the suite restores it and compares
  the row counts against the live database.
- **One alert has fired and recovered** — the suite makes the backups look
  stale, requires an alert, puts them back, and requires the alerting to go
  quiet.
- The machine is healthy by the same definition `lab chaos --check` uses.
- And it has **rebooted** since you armed the check.

**This is a two-phase check.** Build everything, then
`lab check s8-01-build-from-nothing --arm`, then reboot, then run the check
without `--arm`. Arming tells you what is still missing before you spend a
reboot on it.

Fill in `lab.conf` as you go — `LAB_ADMIN_USER`, `EXPECTED_PORTS`,
`EXPECTED_USERS`, the vhosts. The suite holds you to what you wrote down, which
means writing down what you actually built is part of building it.
