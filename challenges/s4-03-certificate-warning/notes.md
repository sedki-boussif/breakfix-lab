# s4-03 — author notes

**What the fault really is.** The certificate nginx serves has been replaced
with one whose `notAfter` is in the past. The key still matches, the names are
still right, the chain is as self-signed as it ever was — only the dates are
wrong, which is why the browser's error names dates specifically.

**Why it is level 3.** The diagnosis is three commands, but the cause is in a
layer the symptom does not obviously implicate — nothing about the application
or nginx's configuration changed — and the useful work is the prevention rather
than the fix. Reissuing a certificate is easy; noticing before your users do is
the exercise.

**Why the reporter has already clicked through.** This is the real damage. A
user who learns that certificate warnings are dismissible has lost the ability to
react to the one that is an actual interception, and that habit is taught by
exactly this kind of unnoticed expiry. The brief says so plainly rather than
leaving it implied, because the lesson is not "renew certificates" but "an
expired certificate trains your users to be phishable".

**The trap.** Issuing a replacement for one day, or for one vhost. The symptom
clears in the browser being tested and returns tomorrow, or returns for the
other two names. `check.sh` requires more than `TLS_MIN_DAYS` remaining and
tests the handshake against **all three** vhosts by SNI.

**`PROVEN=real`.** The certificate mechanics — generating an expired
certificate, reading `notAfter`, computing days remaining, and the TLS handshake
through nginx — are all exercised with real openssl and real nginx.
