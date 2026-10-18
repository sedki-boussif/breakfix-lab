# s2-02 — author notes

**Why a format at all.** The obvious version of this mission asks for six facts
on a screen and checks that six numbers appear somewhere. Specifying
`key: value` costs the reader nothing and buys two things: the check can be
precise about *which* number is wrong, and the script's output becomes
something another script can read. That second property is the habit worth
forming — the next mission, s2-03, is a script that consumes exactly this kind
of output.

**Why plain numbers, explicitly.** `37` not `37%`, `1876` not `1.8G`. A number
with a unit glued to it is a string, and the moment anything wants to compare
it the unit has to be stripped by whoever reads it, which is how `gsub("%", "")`
ends up in four places instead of one. The check enforces it because stating it
in prose does not.

**Why `uptime_seconds` and not an uptime string.** It is the one field with a
genuinely wrong answer that looks right. `uptime` prints prose whose shape
changes with how long the machine has been up — "up 14 min", "up 2 days, 3:14",
"up 1:02" — so a regex over it passes on the machine it was written on and
fails on the next one. `/proc/uptime` is a number. The check also rejects a
Unix timestamp, because `date +%s` is numeric, plausible-looking, large, and
claims the machine booted in 1970; it is the single most common wrong answer
here and no generic "is it a number" assertion catches it.

**Why memory is left open, and the ingredients printed.** "Memory used" has
several defensible definitions and `free`'s `used` column is the one most
people reach for and the one that makes a healthy Linux machine look like it is
about to fall over, because it counts cache as used. Rather than specify the
answer, `break.sh` prints `MemTotal` and `MemAvailable` and says they are
ingredients, the check only requires the figure to be between zero and the
machine's total, and the brief asks which definition was chosen to be recorded
in the report. The decision is the content of the exercise.

**Why `shellcheck` is an assertion.** The repository's own gate is `make lint`,
and holding a script the reader writes to the same standard it holds its own is
the only consistent position. It is also the cheapest possible introduction to
`shellcheck` — run on one short file you wrote yourself, its findings are
legible in a way that running it on someone else's repository never is.

**Why it runs twice.** A script that works once and not twice is usually one
that left a temporary file behind, or whose first run created something the
second tripped over. Comparing the *keys* rather than the values is deliberate:
the values are expected to move between runs, and anything that insisted they
match would be asserting that the machine is idle.

**The trap.** Measuring the wrong filesystem. `df -h` with no argument, or
`df /home`, gives a percentage that is a real number from a real filesystem and
has nothing to do with the root volume filling up. The check compares against
`df -P /` with a two-point tolerance and names both figures when they disagree,
because "37 is not 3" is useless and "the script says 3%, df says 17% for /"
points straight at the cause.

A second, smaller one: `df` without `-P` wraps a long device name onto two
lines, so `awk 'NR==2'` reads half a row and the percentage comes out of the
wrong column. It does not happen on every machine, which is what makes it worth
knowing about rather than discovering.

**Two bugs in this check, both worth recording.**

First, the variable name. `assert_cmd` declares `local out`, and the check
passed it a function that wrote to a global `$out` — shadowed, unset, and under
`set -u` the callback aborted with "unbound variable" before the script under
test ever ran. Every assertion after it failed for the wrong reason. The
variables here are now `outfile` and `outfile2`, and `lib/assert.sh` carries a
note naming the three locals a callback must avoid.

Second, the process-table parse. It kept any line containing a digit and took
the last number on it as the size, so `  2  node` — a rank, a name, and no size
at all — was read as a process using 2 MB. It passed the malformed-line
assertion and then corrupted the ordering assertion, which failed and looked
like a different bug. It is now parsed by position: numeric first field,
numeric last field, at least one field of name between them. Both bugs are the
same shape as the ones this repository keeps finding — an assertion that was
measuring something adjacent to what it claimed.

**`PROVEN=real`.** Needs no systemd, no containers and no applications, so a
container exercises it exactly as the VM would. Verified against a correct
implementation and against seven specific mistakes: `date +%s` for uptime, a
`%` glued to the disk figure, `1.8G` for memory, a three-process table, an
ascending table, a line with no size, a tie in the middle, a name containing a
space, the wrong filesystem, a missing `set -euo pipefail` with a real
`shellcheck` finding, and no script at all.
