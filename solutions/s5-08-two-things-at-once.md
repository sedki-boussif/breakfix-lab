# s5-08 — Two things at once

## Symptom
Two reports eleven minutes apart that contradict each other. First: nothing
loads at all, connection refused, "the server must be off". Then, after a
colleague restarted nginx: the pages load but the leave app returns 502, and the
theses site is fine. He concluded the 502 "was there all along and we just could
not see it".

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `systemctl status nginx` | `failed`, `Job for nginx.service failed` | The first fault. Ruled out "the server is off" — the machine was up the whole time, only nginx was down |
| 2 | `sudo nginx -t` | `unknown directive "proxy_read_timout" in /etc/nginx/sites-available/lab:74` | Names the file and the line. A typo: `timout` for `timeout` |
| 3 | `sudo sed -n '74p' /etc/nginx/sites-available/lab` | the offending line | — |
| 4 | fix, `nginx -t`, `systemctl restart nginx` | nginx starts; pages load; **leaves now returns 502** | This is the moment to be careful: the 502 is newly *visible*, not newly caused |
| 5 | `systemctl status leaves` | active, running | So the upstream is alive and still cannot serve. Ruled out s3-01's shape |
| 6 | `journalctl -u leaves -n 30` | `could not connect to server: Connection refused … port 5432` | Points one layer further down |
| 7 | `systemctl status postgresql` | `inactive (dead)` | The second fault, entirely unrelated to the first |
| 8 | `curl` all three apps after both fixes | all 200 | The part the ticket did not ask for |

**Dead end worth recording — and the important one.** The instinct, at step 4, to
assume the nginx fix caused the 502 and to undo it. It is the wrong move and it
is very tempting: the error appeared immediately after a change. The tell is that
a 502 requires nginx to be *running* — it cannot have been happening while nginx
was down, because nothing could reach the upstream to fail. "Unreachable" and
"working" are not the only two states.

## Root cause
Two independent faults, layered:

1. An invalid directive in the nginx site file, so nginx would not start and
   nothing was reachable.
2. PostgreSQL stopped, so the leave app could not serve.

The second was unobservable while the first was in place.

## Fix
```bash
sudo sed -i '/proxy_read_timout/d' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl restart nginx
sudo systemctl start postgresql
sudo systemctl is-active nginx postgresql
for u in https://stages.lab.invalid/ https://conge.lab.invalid/etoile-formation-conge/ https://theses.lab.invalid/; do
  curl -kfsS -o /dev/null -w "$u %{http_code}\n" "$u"
done
```

In that order, because the second fault cannot be confirmed fixed until the first
one is. And check all three applications at the end: a multi-fault incident is
exactly where a third fault hides, and the only reason we know there were two is
that someone kept looking after the first symptom cleared.

Why not "fix" the 502 by changing the upstream or removing the leave vhost: both
silence the error without serving the application, which is the worst available
outcome — a green dashboard and an unusable app.

## Verification
`nginx -t` valid, nginx active, the database active, all three applications
answering both directly and through the proxy with the vhost's `Host` header, and
no unit left in a failed state.

## Prevention
- **`nginx -t` before every reload or restart**, in a deploy script and by habit.
  A config test turns a total outage into a refusal to apply.
- **Reload rather than restart** where possible: a failed reload leaves the old
  configuration serving, so a bad edit is a non-event instead of an outage. This
  fault only took the site down because the service was restarted.
- **Alert on each dependency separately.** PostgreSQL being down should have
  paged independently of anything about nginx; instead both faults were
  discovered by a person.
- **After any fix, check everything, not the thing that was reported.** The
  habit that found the second fault here is the only reason the incident closed
  correctly.
- **Write down that a new error after a fix is usually a revealed fault**, not a
  caused one. It is the single most useful sentence in this write-up.

## What I did not know before this
How strongly the order of faults constrains what you can observe — the second
fault was not hidden by bad luck but by the first fault being in front of it, and
no amount of looking would have found it earlier. Also that "connection refused"
and "502" are reliable evidence about *which layer* is broken: refused means
nothing is listening, 502 means something is listening and its upstream is not.
