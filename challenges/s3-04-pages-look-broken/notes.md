# s3-04 — author notes

**What the fault really is.** `STATIC_ROOT` is emptied and the WhiteNoise
manifest (`staticfiles.json`) deleted. The application serves HTML perfectly —
it is a working Django app with a working database — but every stylesheet and
script 404s, so the browser renders unstyled HTML. With
`CompressedManifestStaticFilesStorage`, the missing manifest is the second half
of the fault: even restoring the files without rebuilding the manifest leaves
hashed URLs unresolvable.

**Why it is realistic.** A deploy that runs `collectstatic` into a directory
that is then wiped by a cleanup script, a `STATIC_ROOT` on a volume that did not
get mounted, or a well-meant `rm -rf` of what looks like generated clutter.
"Generated files" is exactly the category people feel safe deleting.

**Why the reporter describes it wrongly.** She reports a redesign, confidently
and in detail, and asks for the old version back — which is a request to roll
back a deployment that never happened. Her description is *good evidence*,
though: "no colours, stacked to the left, links are blue and underlined" is a
precise description of CSS not loading. Reading a user's wrong diagnosis for the
right facts is the skill here, and it is the opposite instinct to distrusting
them.

**The trap.** `DEBUG=True`. Django's development static-file serving kicks in,
the page looks correct immediately, and the fault is untouched — while
tracebacks, settings and query details are now exposed to every user. It is the
single most common "fix" for this symptom. `check.sh` refuses it by asking for a
URL that does not exist and asserting the response is a plain 404 rather than
Django's debug page, which is an end-state observation rather than a file read.

**Level 2.** One cause, in a layer the symptom does not obviously implicate, and
the fastest wrong fix is a security regression.
