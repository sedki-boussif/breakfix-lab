# s9-01 — One request in five

## Symptom
Intermittent 502s from the theses API — roughly one request in five — that
cannot be reproduced on demand. Every single-shot test passes.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `for i in $(seq 1 50); do curl -s -o /dev/null -w '%{http_code} ' <url>; done` | A clean pattern: roughly one in three failing | **The decisive step.** Turns "it feels like one in five" into a rate. A rate that is a clean fraction means round-robin selection |
| 2 | `curl` once | 200 | Which is why the reporter could never show anyone. Worth running to feel how misleading it is |
| 3 | `sudo nginx -T \| grep -A10 upstream` | An `upstream theses_api` with three `server` lines | Found the selector |
| 4 | `sudo ss -ltnp \| grep -E '8000\|8009'` | 8000 has gunicorn; **nothing on 8009** | The member that fails |
| 5 | `journalctl -u nginx --since '1 hour ago' \| grep 8009` | `connect() failed (111: Connection refused) while connecting to upstream` | Confirms it, and shows nginx was logging the cause the whole time |

**Dead end worth recording.** Checking the API's own logs. It never saw the
failing requests, because they never reached it — which is itself the clue that
the fault is in front of the application rather than in it.

## Root cause
The nginx upstream for the theses API had three members and one of them pointed
at a port with nothing listening. Round-robin sent every third request there.

## Fix
Repair the member rather than removing it:

```bash
sudo ss -ltnp | grep -E ':(8000|8009)'       # establish what should be on 8009
# then either start the service that belongs there, or correct the address:
sudo sed -i 's|server 127.0.0.1:8009;|server 127.0.0.1:8000;|' \
  /etc/nginx/conf.d/lab-s9-01-upstream.conf
sudo nginx -t && sudo systemctl reload nginx

for i in $(seq 1 100); do curl -s -o /dev/null -w '%{http_code} ' \
  -H 'Host: theses.lab.invalid' http://127.0.0.1/api/health/; done; echo
```

Why not just delete the third member: the capacity was in the configuration for
a reason, and removing it is a capacity decision disguised as a bug fix.
Establish what belonged there first. If the answer is genuinely "nothing", remove
it deliberately and say so — but that is a different change.

**Also worth adding**, and the reason the fault was invisible for so long:

```nginx
server 127.0.0.1:8009 max_fails=3 fail_timeout=30s;
```

nginx will then take a failing member out of rotation by itself. That converts
this fault from "one in three requests fail for ever" into "a few requests fail
once", which is the behaviour you want — and it is off by default for upstreams
with a single server, which is why nobody notices it is missing.

## Verification
A hundred consecutive requests, all 200. The upstream still has all three
members, and every member has something listening on it.

## Prevention
- **Monitor with a loop, not a probe.** A health check that makes one request
  has a two-in-three chance of passing while a third of traffic fails. Three
  requests per check, all of which must pass.
- **`max_fails` / `fail_timeout` on every multi-member upstream**, so a dead
  member removes itself.
- **Alert on the 5xx *rate*, not on 5xx presence.** This fault produced a steady
  33% error rate that no threshold was watching.

## What I did not know before this
That a fraction is a diagnosis. "One in three" and "one in five" are not vague
reports — they are strong evidence of round-robin over three or five things, and
counting the things is then the whole investigation.
