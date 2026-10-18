# s4-02 — author notes

**What the fault really is.** A nameserver that does not answer is configured as
the resolver. Lookups go to it, wait out the timeout and fail. Connectivity is
untouched, so everything that uses an address keeps working, and everything that
uses a name hangs.

**Why the apps keep working.** The three applications reach their databases by
compose service name (resolved by Docker's embedded DNS, not the host resolver),
by `127.0.0.1`, or over a unix socket. None of those paths touches
`/etc/resolv.conf`. That selectivity is the diagnostic signal and the reason the
reporter is confused.

**Where the configuration really lives, on 24.04.** `/etc/resolv.conf` is a
symlink to a stub that `systemd-resolved` owns, so editing it appears to work and
is reverted on the next restart. The break edits `resolved.conf` when resolved
is present and the file directly when it is not, and the hints point at both.

**The trap.** Editing `/etc/resolv.conf` by hand. `dig` starts working, the
challenge looks solved, and the next `systemctl restart systemd-resolved` — or
the next reboot — puts the broken nameserver back. The check therefore restarts
the resolver before its final assertion, so a fix that does not survive that
does not pass.

**`PROVEN=unproven`.** A container shares the host's resolver and has no
systemd-resolved, so the half that matters cannot be exercised honestly here.
