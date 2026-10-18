**The goal.** Build monitoring that tells you about a problem before a user
does, and prove it by making each alert fire.

**Three alerts, and they are the specified set:**

1. **A filesystem over 80% full.** Any filesystem, not only `/` — the one that
   fills is rarely the one you were watching.
2. **A service down.** Any of the units or containers the three applications
   depend on.
3. **A certificate expiring within 14 days.** The one in `$TLS_CERT`.

**How you build it is yours.** Prometheus with `node_exporter` and Alertmanager
is the conventional answer and the one worth knowing. Netdata is a legitimate
alternative and much faster to stand up. A shell script on a systemd timer is
also a legitimate answer for three rules on one machine, and if you choose it,
say in the report why — because at three rules it is the right call and at
thirty it is not, and knowing where that line is matters more than which side
of it you picked today.

**What is not yours to choose: the alerts have to arrive somewhere.** Whatever
you build must append its alerts to `$S6_03_ALERT_LOG`, one line per alert,
each line naming which condition fired. This is the same arrangement as the
backup dead-man's-switch in s7-01, for the same reason: an alert that exists
only inside a dashboard is an alert nobody is woken by, and a check cannot
read a dashboard. A real notification channel — email, a webhook, a phone —
would be an additional destination, not a replacement for this one.

Each line must also make clear when the condition **clears**. A level that
never recovers is a level nobody reads after the second week.

**The standard this will be checked against.** The check does not read your
configuration and agree that it looks correct. It causes all three conditions,
one at a time, and requires an alert each time:

- It creates a **bounded loopback filesystem** and fills it past 80%. Your
  monitoring must notice a filesystem it has never seen before, which is the
  point of "any filesystem" — a rule hard-coded to `/` will not pass.
- It **stops a service**, and requires an alert naming it. Then starts it and
  requires the alert to clear.
- It installs a certificate **expiring in seven days** where `$TLS_CERT`
  points, requires the alert, and puts your real certificate back.
- And it requires **no alerts at all** in a quiet period first, because
  monitoring that alerts constantly has the same information content as
  monitoring that never alerts.

**This check changes things on purpose and puts them back.** It fills a
filesystem of its own making, stops and starts one service, and swaps the TLS
certificate for a short-lived one and back. All three are restored on every
exit path, including a failed one. Your real certificate is copied aside first;
if anything goes wrong, the copy is named in the output.

**Set these in `lab.conf` before you start:** `S6_03_ALERT_LOG`, and
`S6_03_RELOAD` if your monitoring needs a command to re-read its rules.
