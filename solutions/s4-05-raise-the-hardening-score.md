# s4-05 — Raise the hardening score

## The goal
Turn "hardened" into a number with a date on it, improve it deliberately, and
record what I rejected.

## Baseline
```bash
sudo lynis audit system
sudo awk -F= '/^hardening_index=/{print $2}' /var/log/lynis-report.dat
```
Baseline index: **record yours**. Stored in `LYNIS_BASELINE` so the comparison
is against a number rather than a memory.

## The five I fixed, and why

1. **Password policy** (`libpam-pwquality`, minimum length and complexity).
   Cheap, and relevant even on a key-only box because `sudo` and local accounts
   still have passwords.
2. **Kernel sysctls** — `net.ipv4.conf.all.rp_filter=1`,
   `net.ipv4.conf.all.accept_redirects=0`, `kernel.dmesg_restrict=1`. One file in
   `/etc/sysctl.d/`, no behavioural risk for this workload.
3. **`/etc/cron.*` and `at` permissions.** Directory modes that allowed more
   than root to read scheduled work. Free to fix, and directly relevant: s7-06
   is an intrusion whose persistence lives in `/etc/cron.d`.
4. **A login banner and `/etc/issue.net`.** Trivial, and lynis wants it; more
   usefully, a banner is where to put the "this is a lab, nothing here is real"
   notice.
5. **`auditd` installed with a minimal ruleset** — execve and identity changes
   only. The expensive suggestion done cheaply: a small ruleset I will actually
   read beats a comprehensive one I will ignore.

## What I rejected, and why — the half worth keeping

- **Disabling USB storage and FireWire modules.** A VM with no physical ports.
  Points for nothing, and one more thing to remember if the hypervisor ever
  attaches a device.
- **AppArmor profiles for every service.** Real value, wrong order: profiling
  three applications properly is a week, and doing it badly produces denials
  that look like application bugs. Written down as a deliberate deferral rather
  than an oversight.
- **Mount options (`nodev`, `nosuid`) on `/var`.** `/var/lib/docker` lives there
  and Docker needs device nodes. Accepting this suggestion uncritically would
  have broken every container on the next reboot — which is exactly the failure
  mode the brief warns about.
- **Disabling IPv6.** Suggested, and wrong: the correct answer is to configure
  it, not to remove it, and nothing here depends on it being off.

## Verification
The index improved against the recorded baseline. `sudo sshd -T` reports
`permitrootlogin no`, `passwordauthentication no`, `pubkeyauthentication yes` —
asked of sshd rather than read from a file, because a drop-in in
`sshd_config.d/` beats the main config. And the listening ports match
`EXPECTED_PORTS` **in both directions**: nothing extra, and nothing expected
gone.

## What I did not know before this
That a hardening index is trivially gameable — several suggestions raise it
without changing this machine's exposure at all — so the score is only
meaningful next to the list of what you refused. And that the dangerous
suggestions are the plausible ones: `nodev` on `/var` reads like obvious good
practice and would have taken every container down.
