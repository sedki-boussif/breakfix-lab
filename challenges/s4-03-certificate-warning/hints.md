The browser already told you which check failed: `ERR_CERT_DATE_INVALID` is about dates, not about trust chains or names. That narrows it to one question before you touch the server.
Ask the server directly rather than through a browser: `openssl s_client -connect conge.lab.invalid:443 -servername conge.lab.invalid </dev/null 2>/dev/null | openssl x509 -noout -dates -subject`.
`notAfter` is in the past. So the certificate is expired, and nothing is wrong with nginx, the key pairing, or the hostnames.
Find which file nginx is actually serving — `grep -r ssl_certificate /etc/nginx/` — and check that file's dates with `openssl x509 -in <file> -noout -dates`. It is worth confirming you are looking at the same file the running server is.
Issue a replacement with a sensible lifetime and the same subject alternative names (all three lab vhosts), then `nginx -t` and reload. The lab's `lab.conf` records where the certificate and key live.
The expiry is the symptom; nobody noticing for however long it was expired is the fault. The check requires more than fourteen days remaining, and the report should say what will tell you next time.
