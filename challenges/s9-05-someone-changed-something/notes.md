# s9-05 — author notes

**What the fault really is.** The system timezone was changed, and systemd
interprets `OnCalendar=` in local time. Every timer on the machine moved by the
offset. The nightly job did not fail, was not disabled, and has nothing wrong
with it — it is simply now scheduled at a different moment than the person
expecting its output.

**Why the change is "unrelated".** It was made for a good reason, by someone
competent, to fix a real complaint about report timestamps, and it has no
visible connection to a scheduled job. That is the level-4 property: the cause is
a change in a different domain, and nothing in the symptom points at it.

**Why two reporters who have not spoken.** The whole challenge is in the gap.
Both messages are in the same channel, a day apart, and the first one contains
the answer to the second. Reading backwards through recent changes — rather than
forwards from the symptom — is the move, and it is the one people skip because
the symptom feels like it should be diagnosable on its own.

**Why a timezone and not an MTU or a locale.** All three were in the
specification. The timezone is the one that is deterministic, safe, and
reversible on any hardware: an MTU change needs real interfaces to be
interesting, and a locale change produces failures that vary with the tool.
This one produces exactly the same behaviour everywhere.

**The trap.** Making the report appear. Running the job by hand, or moving the
`OnCalendar` time until it lines up again, both produce output and leave the
machine's schedule silently coupled to its timezone — which will move again at
the next daylight-saving change, in March, when nobody is thinking about this.
`check.sh` requires the report to **name the timezone change as the cause**,
because a fix without the diagnosis is a fix with an expiry date.

**The decision, which has no single right answer.** Pin the timer to UTC, or
keep local time deliberately. The notes do not prescribe one: the solution
argues for UTC for machine schedules and local time for human-facing output, and
the report is expected to say which was chosen and why.

**`PROVEN=real`.** `timedatectl`, timer next-elapse arithmetic and the offset
are all real and deterministic.
