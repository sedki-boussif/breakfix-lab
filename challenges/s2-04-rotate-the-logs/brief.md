**The goal.** `$LEAVES_LOG` grows and nothing truncates it. Write a logrotate
rule that rotates it **daily**, keeps **7**, and **compresses** the old ones —
and that leaves the application still writing afterwards.

The rule goes in `$S2_04_LOGROTATE_CONF`.

**The four properties:**

1. **Daily**, and only on a schedule — not `size`-based. Both are defensible in
   general; daily is what this asks for, because a predictable filename is
   worth more here than a predictable file size.
2. **`rotate 7`** — a week of history, then gone.
3. **Compressed.** `compress`, and `delaycompress` if you want the most recent
   rotation left readable, which is usually the one you want to read.
4. **The application keeps writing to the new file.** This is the property that
   is actually difficult, and the one the check spends most of its time on.

**Why the fourth is the hard one.** `logrotate` renames the file. It does not
tell the process that was writing to it, and a process that opened a file holds
that file — not that *name* — until it is told otherwise. So the day after an
unfinished rotation, the new log is empty, the application is still writing
happily into a file with no name, and the only way to see the logs at all is
through `/proc/<pid>/fd/`. The disk space is not freed either, which is `s5-03`
arriving by appointment instead of by accident.

Two ways out, and they are genuinely different:

- **`postrotate`** — signal the process to reopen its files. Gunicorn reopens
  on `SIGUSR1`. The rule has to find the right process, and
  `systemctl kill -s USR1 <unit>` is more reliable than a `pidfile` that may
  not exist.
- **`copytruncate`** — copy the file aside and truncate the original in place,
  so the file handle stays valid. Simpler, needs no cooperation from the
  application, and loses anything written between the copy and the truncate.

Either passes. **Say which you chose and why in the report** — that choice is
the content of this mission, and the reasoning matters more than the outcome.

**The standard this will be checked against:**

- The rule exists, covers `$LEAVES_LOG`, and `logrotate --debug` parses it with
  no complaints.
- It specifies `daily`, `rotate 7`, and compression.
- A forced rotation produces a rotated file that is **actually compressed** —
  tested by decompressing it, not by looking at the suffix.
- After the rotation, the application writes again and **the new file grows**.
  The check makes a request and watches the file, and this is the assertion
  that catches an unfinished `postrotate`.
- No process is left holding a deleted copy of the log.
- `logrotate` is run the way the system runs it, so a rule that only works with
  `-f` by hand does not pass.
