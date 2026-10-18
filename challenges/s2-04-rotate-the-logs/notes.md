# s2-04 — author notes

**Why this is a level 2 and not a level 1.** Three of the four properties are a
five-line configuration file. The fourth — the application still writing
afterwards — is a different kind of problem, and it is the only one that cannot
be satisfied by reading the manual page for `logrotate`. It requires knowing
that a process holds an open *file* rather than a filename, which is a fact
about Unix rather than a fact about logrotate, and that is why it is worth a
whole mission.

**Why the log is gunicorn's and not nginx's.** `SETUP.md` section 6 points the
leaves access log at a file on purpose, with a note saying not to send it to the
journal instead. The journal cannot be rotated by logrotate and the mission
would be vacuous. Gunicorn also happens to be the better teacher here: it
reopens its files on `SIGUSR1`, so `postrotate` has something real to do, and
the alternative — `copytruncate` — is a genuinely different trade-off rather
than a worse version of the same thing.

**Why the check accepts either answer.** `postrotate` and `copytruncate` solve
the same problem differently: one asks the application to cooperate and is
precise, the other needs no cooperation and loses whatever is written between
the copy and the truncate. Neither is correct in general. What is being taught
is that the choice exists and that it has a cost either way, so the brief
requires the choice to be recorded in the report and the check holds only the
outcome.

**Why compression is tested by decompressing.** A file named `.gz` that is not
gzip passes a suffix check, and the suffix is the part logrotate renames before
it runs the compressor. `gzip -t` either succeeds or it does not. This is the
same principle as the absence controls elsewhere in the lab: test the claim,
not the thing that usually accompanies the claim.

**Why the system's own logrotate run is asserted.** A rule in
`/etc/logrotate.d/` that `logrotate.conf` does not include is a file nobody
reads, and the failure mode is silence — the rule is correct, the file is in
the right directory, and nothing ever rotates. logrotate skips filenames with
certain suffixes, and some versions skip any filename containing a dot, which
is how `leaves.conf` becomes a rule that only works when you run it by hand.
Asserting that `logrotate --debug /etc/logrotate.conf` reaches the log is what
catches it, and it is also the assertion that a hand-only rule cannot satisfy.

**The ordering bug in this check, which took a false failure to find.**
`delaycompress` leaves the newest rotation uncompressed deliberately, so one
rotation can never demonstrate compression under it and a second is needed. The
first version forced that second rotation immediately after the first — where it
reads naturally — and it did nothing at all, because the new log was still empty
and `notifempty` skips an empty file. The result was a correct rule failing the
compression assertion with a message suggesting the reader run the check twice.
The second rotation now happens *after* the requests that refill the log, which
is less tidy to read and is the only order that works.

**The trap.** A rule with every stated property and no `postrotate` and no
`copytruncate`. It parses, it rotates, it compresses, it keeps seven, and from
the next day the log is empty while the application writes happily into a file
with no name. The disk space is not freed either — this is `s5-03` arriving by
appointment rather than by accident. The check catches it twice over: the new
file does not grow, and the absence assertion finds a process holding a deleted
copy and reports "still present". Verified: the rule with neither directive
fails exactly those two assertions and passes the other nine.

**`PROVEN=mock-process`.** The application was replaced by a small HTTP server
that holds its log open, appends on each request, and reopens on `SIGUSR1` —
which is the behaviour that matters, and is what gunicorn does. Real
`logrotate` 3.21 from Ubuntu 24.04's archive, real `gzip`, real `/proc` scan.
What is mocked is only the application, which is why this is mock rather than
real. Verified against six rules: `postrotate`, `copytruncate`, neither,
`weekly`/`rotate 3`/no compression, a rule naming a path that does not exist,
and no rule at all.
