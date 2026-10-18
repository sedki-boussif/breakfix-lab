# s7-06 — author notes

**The four traces, and why these four.** They are chosen so that cleaning up in
the obvious order does not work:

1. **A hidden account with a login shell** (`svc-backup`, uid in the normal
   range, name chosen to look like infrastructure).
2. **An unknown key in `authorized_keys`** — the actual access, and the thing
   that matters.
3. **A cron job that re-adds the key** every few minutes. This is the
   persistence, and it means removing the key alone accomplishes nothing.
4. **A process listening on a high port** under a plausible name, which is what
   the provider noticed.

The reinforcement is the lesson: a responder who finds and removes the key, the
account and the process, in that order, and then declares the machine clean,
will find the key back within minutes. The only ordering that works is to find
the persistence first.

**Why level 5.** It is the first challenge with no symptom to work backwards
from — the applications are fine, nothing failed, and the only evidence is a
third party's assertion. Everything comes from enumeration rather than
diagnosis, and the challenge is complete-coverage rather than root-cause.

**Why the reporter is a provider's abuse notice.** Factual, timestamped,
impersonal, and arriving through a channel that bypasses all of your own
monitoring — which is realistic, and is also the point: the machine's own
instruments did not notice, so none of them can be trusted as proof of absence.
It also establishes the one thing you do know, a start time, which is what makes
the log review tractable.

**The trap.** Declaring it clean after removing what you found. `check.sh`
removes nothing and waits: it verifies the four traces are absent, and
specifically **triggers the persistence window** by waiting out the cron
interval and checking the key has not come back. A cleanup that leaves the cron
job passes a casual inspection and fails this.

The second trap is reporting only what was fixed. The check requires the report
to name **all four** traces and how each was found, because in a real incident
the list of what you found is the deliverable — it is what tells the next person
whether you looked everywhere or stopped at the first thing.

**Safety.** The planted account has no password and is locked; the key is a
generated throwaway with an obviously-fake comment; the listener binds loopback
only; the cron job runs every two minutes and does nothing but re-add the key.
Nothing here touches your own `authorized_keys`, your own account, or sshd's
configuration — §2.6 forbids changing SSH access outside the one challenge that
is about that, and this is not it.
