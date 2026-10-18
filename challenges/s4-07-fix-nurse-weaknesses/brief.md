**The goal.** Remove two real weaknesses from an application you actually own,
and leave a diff small enough that you would merge it.

`nurse` has two settings that are wrong in the same way: both fail *open*.

1. **`SECRET_KEY` falls back to a hard-coded value** when the environment
   variable is missing. A deployment that forgets to set it starts anyway, with
   a key that is in the repository and therefore public. Every session cookie,
   password-reset token and signed value on that deployment is forgeable by
   anyone who can read the source.
2. **`DEBUG` defaults to `True`** when unset. A deployment that forgets it
   serves full tracebacks — settings, SQL, file paths — to anyone who triggers
   an error.

In both cases the safe state requires someone to remember something, and the
unsafe state is the default. Invert that.

**The standard this will be checked against:**

1. With `SECRET_KEY` **unset**, the application **refuses to start**, with an
   error that names the variable.
2. With it set, the application answers 200 as before.
3. `DEBUG` is **false** when unset, and the running deployment has it false.
4. The diff is **small** — settings only, no restructuring — and the commit
   message explains why, because this is a real change to a public repository.

**This is not the lab's code.** It is yours, on your own GitHub. Read
`settings_production.py` and the settings module the deployment actually uses
before changing anything, and edit the canonical copy — remember the duplicate
files at that repository's root.
