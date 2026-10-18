# s4-03 — Browsers warn about the certificate

## Symptom
Browsers show `NET::ERR_CERT_DATE_INVALID` for the leave site. Three users
affected. One of them clicked through the warning and continued, and reported
that "everything works".

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | the browser error itself | `ERR_CERT_DATE_INVALID` | Dates, specifically. Not the chain, not the names, not a protocol mismatch. The browser has already done the diagnosis |
| 2 | `openssl s_client -connect conge.lab.invalid:443 -servername conge.lab.invalid </dev/null \| openssl x509 -noout -dates -subject` | `notAfter` in the past | Confirms it from the server rather than from a cached browser state |
| 3 | `grep -rn ssl_certificate /etc/nginx/` | Which file nginx serves | Worth confirming: the file you are about to inspect must be the file in use |
| 4 | `openssl x509 -in /etc/nginx/tls/lab.crt -noout -dates` | Expired 35 days ago | — |
| 5 | `openssl x509 -noout -ext subjectAltName` | All three vhosts present | The replacement must cover all three, not just the one that was reported |

**Dead end worth recording.** Checking `nginx -t` and reloading first. It passes
— nginx will happily serve an expired certificate, because expiry is the
client's judgement, not the server's. That is worth knowing: the server has no
opinion about it and will never tell you.

## Root cause
The certificate nginx serves expired 35 days ago. The key still matched and the
names were still correct; only the dates were wrong.

## Fix
```bash
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/tls/lab.key -out /etc/nginx/tls/lab.crt \
  -subj "/CN=stages.lab.invalid" \
  -addext "subjectAltName=DNS:stages.lab.invalid,DNS:conge.lab.invalid,DNS:theses.lab.invalid"
sudo chmod 600 /etc/nginx/tls/lab.key
sudo nginx -t && sudo systemctl reload nginx
```

All three names, and a real lifetime. A certificate for one name fixes the
reported symptom and leaves the other two broken; a one-day certificate fixes it
until tomorrow. The check requires more than fourteen days and tests each vhost
by SNI, which is how both shortcuts fail.

## Verification
More than `TLS_MIN_DAYS` remaining on the file nginx serves; the handshake
succeeds for all three vhosts by SNI and each is in `subjectAltName`; HTTPS
returns 200 through the proxy.

## Prevention — the actual point of this challenge
- **Alert at 14 days, from outside.** The expiry was knowable 90 days in
  advance and nobody was told. `openssl s_client` in a cron job, or the
  certificate check in s6-03's alert set.
- **Automate renewal where the names are public** (certbot), and where they are
  not — as here, with `.invalid` names that no CA can validate — put the renewal
  in the same timer as everything else and alert on its marker going stale, the
  s7-01 pattern.
- **Treat "a user clicked through" as the incident.** Someone who learns that
  certificate warnings are dismissible has lost the ability to react to the one
  that is a real interception. That habit is taught by unnoticed expiries, and it
  is the expensive part of this outage.

## What I did not know before this
That nginx serves an expired certificate without complaint — the server never
checks, so the only thing that will ever tell you is a client or a monitor. And
that `openssl s_client` reports a self-signed chain error *before* it gets to
dates, so on a self-signed deployment the file's `notAfter` is the only reliable
place to look.
