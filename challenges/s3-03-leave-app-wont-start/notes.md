# s3-03 — author notes

**What the fault really is.** `SECRET_KEY` is removed from the environment file
the unit loads. The app uses `python-decouple` with no default for it, so Django
raises at import and gunicorn exits before binding. The service never listens,
and because `break.sh` restarts it repeatedly, the unit also hits its start
limit — so even a correct fix appears not to work until `systemctl reset-failed`.

**Why it is realistic.** A missing default is the *right* design: the app refuses
to run rather than running with a predictable key. The failure mode that creates
is this one — a config line that looks like noise to someone who did not write
it. "I was tidying up" is how most of these arrive.

**Why the reporter is a colleague who already intervened.** Two useful effects.
First, the brief contains a false statement — "I have put the line back" — and
checking the claim rather than accepting it is the first move. Second, his
repeated restarts caused the start-limit state, so part of what has to be undone
is the *remediation*, not the original change. That is extremely common and
rarely taught.

**The trap.** Two of them, both enforced:

1. **Any value will start the app.** `SECRET_KEY=changeme` works perfectly, and
   Django will not complain. `check.sh` requires at least 40 characters and
   refuses any value that appears anywhere in the application's repository —
   example files and committed defaults included. A key lifted from the repo or
   from git history is not a secret.
2. **Hard-coding it in `settings.py`** also starts the app, and leaves the
   environment file still wrong, so the next deploy or container rebuild breaks
   again. `check.sh` therefore requires the value to be present in the file the
   unit actually reads.

This is one of the few places a check reads a file rather than only observing
behaviour. That is deliberate: both wrong fixes are invisible from outside, and
"the page answers" cannot distinguish them.

**Level 2.** One missing value, but the brief misleads, the start limit obscures
the fix, and the two obvious shortcuts are both wrong.
