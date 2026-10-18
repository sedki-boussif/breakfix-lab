# s4-07 — author notes

**Why this is in the lab at all.** Every other challenge is practice. This one
is a real patch to a real public repository, chosen because the two weaknesses
are the textbook examples of the same mistake: **the safe state requires
remembering something, and the unsafe state is the default.** Inverting that is
the single most transferable idea in configuration security.

**What makes each one dangerous, concretely.** A hard-coded `SECRET_KEY`
fallback means a deployment that forgets the variable gets a key that is public
in the repository — and Django derives session cookies, password-reset tokens
and all signed values from it, so every one of those becomes forgeable by
anyone who can read the source. `DEBUG=True` by default means an unconfigured
deployment serves its own settings, SQL and paths to anyone who can cause a 500.

**The Python detail worth knowing.** `bool('False')` is `True`, so
`DEBUG = bool(os.environ.get('DEBUG', 'True'))` is wrong in two directions at
once: unset means on, and the string `'False'` also means on. The hint points at
it because it is how this bug is almost always written.

**Compare with `leaves`.** That application already does it right —
`SECRET_KEY = config('SECRET_KEY')` with no default, which is exactly why s3-03
exists: the app dies at import when the variable is missing. The lesson is that
s3-03's "fault" is the correct behaviour, and this mission is making `nurse`
behave the same way.

**The trap.** Setting the environment variables and calling it done. The
deployment then works and the *code* still fails open, so the next deployment —
a container, a colleague's laptop, a rebuild — is insecure again.
`check.sh` therefore runs the application **with `SECRET_KEY` removed from the
environment** and requires it to refuse to start. Fixing the config instead of
the code does not pass.

**`PROVEN=unproven`.** It needs the real repository. The check is written
against the deployment this lab sets up in SETUP.md §7 — a systemd unit with an
`EnvironmentFile` — and the first thing to confirm on the VM is that the
settings module it reads is the one the check inspects.
