# s3-03 — The leave app will not start at all

## Symptom
The leave application does not start. A colleague removed a line from the
environment file while tidying, restarted the service several times, rebooted,
and reports having put the line back.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl status leaves` | `failed`, and `start request repeated too quickly` | Ruled out 203/EXEC — this is not a missing binary. It also warned that the start limit is now in play, so the next few restarts will refuse regardless of the config |
| 2 | `journalctl -u leaves -n 80 --no-pager` | A Python traceback ending in `decouple.UndefinedValueError: SECRET_KEY not found. Declare it as envvar or define a default value.` | Ruled out the database, the port, gunicorn's module path and the virtualenv. Python ran, Django imported, settings failed |
| 3 | `systemctl show -p EnvironmentFiles leaves` | `/etc/leaves/leaves.env` | Confirms which file matters, rather than assuming |
| 4 | `sudo grep -c SECRET_KEY /etc/leaves/leaves.env` | `0` | The claim in the ticket — "I have put the line back" — is false. He put something back, or thought he did |
| 5 | `cd /opt/leaves && git log -p -- '*settings*' \| grep -i secret` | A committed example value | Not a fix: anything in the history is public. Worth looking at only to know which value **not** to use |

**Dead end worth recording.** Restarting the service twice more before reading
the traceback, which deepened the start-limit problem and briefly made it look
like the service was refusing for a different reason.

## Root cause
`SECRET_KEY` was missing from `/etc/leaves/leaves.env`. The application reads its
settings with `python-decouple` and declares `SECRET_KEY` with no default, so a
missing variable raises at import and gunicorn exits before binding. The repeated
restarts then tripped the unit's start limit, which obscured the fix.

## Fix
```bash
printf 'SECRET_KEY=%s\n' "$(openssl rand -hex 32)" | sudo tee -a /etc/leaves/leaves.env
sudo chmod 640 /etc/leaves/leaves.env
sudo systemctl reset-failed leaves
sudo systemctl restart leaves
```

`reset-failed` first, or the restart is refused and the fix looks ineffective.

Why a generated value rather than any value: `SECRET_KEY=changeme` starts the app
perfectly. Django's session cookies, password-reset tokens and signed cookies are
all derived from it, so a guessable key means forgeable sessions. A value taken
from the repository or from git history has already been published and is worth
no more than `changeme`. 64 hex characters from `openssl rand` costs nothing.

Why the environment file rather than `settings.py`: hard-coding it there also
starts the app, and puts the secret in version control while leaving the
environment file still wrong for the next deploy.

## Verification
The app answers 200 under the URL prefix; `SECRET_KEY` is present in the file the
unit reads, is at least 40 characters, and does not appear anywhere in the
application's tree; and the app still answers after a full `systemctl restart`.

## Prevention
- **The app's own design already prevented the worse outcome.** No default meant
  it refused to run rather than running with a predictable key. The fix is not to
  add a default.
- **A comment on the line.** `# required: Django signing key, see docs` would
  have stopped the tidy-up. Configuration that looks like junk gets deleted.
- **A preflight check before the service starts** — `ExecStartPre` asserting the
  required variables are present — turns a traceback into a one-line refusal
  naming the variable.
- **`visudo`-style validation for env files**: a deploy script that greps for the
  required keys and refuses to restart without them.
- **Record what you removed.** Half of this incident was the absence of a note.

## What I did not know before this
A unit that has exhausted `StartLimitBurst` keeps refusing to start even once the
configuration is correct, until `systemctl reset-failed`. That alone can make a
good fix look like a failed one, and it is caused by the panicking that follows
the original fault rather than by the fault.
