# s4-07 — Fix the weaknesses in nurse

## The goal
Remove two fail-open settings from a repository I own, with a diff I would
merge.

## What was wrong

```python
# before — both of these fail OPEN
SECRET_KEY = os.environ.get('SECRET_KEY', 'django-insecure-<literal in the repo>')
DEBUG = os.environ.get('DEBUG', 'True') == 'True'
```

1. **`SECRET_KEY` with a fallback.** A deployment that forgets the variable
   starts anyway with a key that is in the repository, therefore public. Django
   derives session cookies, password-reset tokens and every signed value from
   it, so all of them become forgeable by anyone who can read the source.
2. **`DEBUG` defaulting to on.** A deployment that forgets it serves tracebacks,
   settings, SQL and paths to anyone who can cause a 500.

The shape is identical in both: **the safe state requires remembering
something, and the unsafe state is the default.**

## The patch

```python
# after
from django.core.exceptions import ImproperlyConfigured

SECRET_KEY = os.environ.get('SECRET_KEY')
if not SECRET_KEY:
    raise ImproperlyConfigured(
        "SECRET_KEY is not set. Generate one and put it in the environment: "
        "python -c 'import secrets; print(secrets.token_urlsafe(50))'"
    )

DEBUG = os.environ.get('DEBUG', 'false').strip().lower() in ('1', 'true', 'yes', 'on')
```

Two things worth noting. The error **names the variable and says what to do**,
because an `ImproperlyConfigured` with a useful message is the difference
between a five-second fix and a twenty-minute one for whoever deploys it next.
And `DEBUG` parses an explicit affirmative rather than truthiness: `bool('False')`
is `True` in Python, which is how the original bug is almost always written.

Settings file only. Four lines added, two changed. The commit message says what
and why, because this is a public repository with my name on it.

## Verification
With `SECRET_KEY` removed from an otherwise complete environment, `manage.py
check` **fails** and the message names the variable. With it set, the checks
pass and the API answers 200. With `DEBUG` unset, `settings.DEBUG` is `False`.
The running deployment returns a plain 404 for a missing URL rather than a
Django debug page. And the diff is three files or fewer.

## Why this matters more than it looks
`leaves` already does it correctly — `SECRET_KEY = config('SECRET_KEY')` with no
default — and that is precisely why s3-03 exists as a challenge: the app dies at
import when the variable is missing, and **that is the correct behaviour**. The
same property that makes s3-03 an incident is what makes it safe. An application
that refuses to start is telling you something; one that starts insecurely is
not.

## What I did not know before this
That `bool('False')` is `True`, and therefore that
`bool(os.environ.get('DEBUG', 'True'))` is wrong twice over — unset means on,
and the literal string `'False'` also means on. Also that the fix for both
weaknesses is the same single idea, which makes it worth carrying as a rule
rather than as two facts: **configuration should fail closed, loudly, naming
what is missing.**
