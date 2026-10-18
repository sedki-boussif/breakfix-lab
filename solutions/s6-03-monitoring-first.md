# s6-03 — Monitoring that tells you first

## The goal
Three alerts — a filesystem over 80%, a service down, a certificate inside 14
days — each one proved by making it fire.

## Choosing the shape

| | Setup cost | Right when |
|---|---|---|
| Prometheus + node_exporter + Alertmanager | three services, a lot of YAML | you have many hosts, want history, or will end up with thirty rules |
| Netdata | one package, alerts work out of the box | you want it this afternoon and one machine |
| A script on a systemd timer | twenty lines | three rules on one machine, and you would rather own the twenty lines than the three services |

At three rules on one VM the script is the honest answer, and that is what is
written out below — with the Prometheus expressions alongside, because those
are what you will need the first time there are two machines. Whichever you
pick, write the reason in the report: knowing where the line is matters more
than which side of it you are on today.

## The script version

```bash
#!/usr/bin/env bash
# /usr/local/sbin/labmon.sh — three rules, alerting on state CHANGE.
set -uo pipefail

ALOG=/var/log/lab-monitor-alerts.log
STATE=/var/lib/breakfix-lab/monitor-state
CERT=/etc/nginx/tls/lab.crt
mkdir -p "$(dirname "$STATE")"; touch "$STATE"

say()  { printf '%s %s %s\n' "$(date -Is)" "$1" "$2" >> "$ALOG"; }
was()  { grep -m1 "^${1}=" "$STATE" 2>/dev/null | cut -d= -f2; }
now_() { grep -v "^${1}=" "$STATE" > "${STATE}.n" 2>/dev/null || true
         printf '%s=%s\n' "$1" "$2" >> "${STATE}.n"; mv "${STATE}.n" "$STATE"; }

# change <key> <firing|ok> <alert text> <recovery text>
change() {
  [[ "$(was "$1")" == "$2" ]] && return 0
  now_ "$1" "$2"
  if [[ "$2" == firing ]]; then say ALERT "$3"; else say RESOLVED "$4"; fi
}

# 1. ANY filesystem over 80% — the one that fills is never the one you watched.
worst=0; worstfs=""
while read -r pct target; do
  [[ "$pct" =~ ^[0-9]+$ ]] || continue
  (( pct > worst )) && { worst="$pct"; worstfs="$target"; }
done < <(df -P --output=pcent,target | tail -n +2 | tr -d '%')
if (( worst > 80 )); then
  change disk firing "disk: filesystem ${worstfs} is ${worst}% full" ""
else
  change disk ok "" "disk: every filesystem is under 80% (worst ${worst}%)"
fi

# 2. A service down.
for unit in nginx postgresql leaves nurse-api docker; do
  systemctl list-unit-files "${unit}.service" >/dev/null 2>&1 || continue
  if systemctl is-active --quiet "${unit}.service"; then
    change "svc_${unit}" ok "" "service: ${unit} is up again"
  else
    change "svc_${unit}" firing "service: ${unit} is down" ""
  fi
done

# 3. A certificate inside 14 days.
end="$(openssl x509 -in "$CERT" -noout -enddate 2>/dev/null | cut -d= -f2)"
if [[ -n "$end" ]]; then
  left=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
  if (( left < 14 )); then
    change cert firing "cert: ${CERT} expires in ${left} days" ""
  else
    change cert ok "" "cert: ${CERT} has ${left} days left"
  fi
fi
```

On a timer, every minute:

```ini
# /etc/systemd/system/labmon.timer
[Timer]
OnCalendar=*:0/1
Persistent=true
```

## The Prometheus expressions, for when there are two machines

```yaml
groups:
  - name: lab
    rules:
      # No instance or mountpoint filter: that is what "any filesystem" means.
      - alert: FilesystemFilling
        expr: |
          (node_filesystem_avail_bytes{fstype!~"tmpfs|squashfs"}
           / node_filesystem_size_bytes{fstype!~"tmpfs|squashfs"}) < 0.20
        for: 5m
      - alert: ServiceDown
        expr: node_systemd_unit_state{state="active"} == 0
        for: 2m
      # From the blackbox exporter: what a CLIENT gets, not what is on disk.
      - alert: CertificateExpiring
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 14
        for: 1h
```

Alertmanager still needs a receiver that appends to the log — a webhook into a
two-line script is enough, and it is the half that is usually missing.

## Alert on the change, not the state

This is the difference between monitoring people read and monitoring people
filter. A rule that writes a line every evaluation cycle while a condition
holds produces several hundred lines overnight; the three-hundredth is the one
that trains everybody to ignore the channel. Keep the last state and write only
on a transition — and write one when it ends, because an alert that never
clears is one nobody can tell is still true.

## Proving each one

```bash
# 1. Disk — on a filesystem of your own, never on /
sudo truncate -s 200M /srv/lab-scratch/monitor/ballast
# 2. Service
sudo systemctl stop leaves && sleep 90 && sudo systemctl start leaves
# 3. Certificate
sudo cp /etc/nginx/tls/lab.crt /root/lab.crt.real
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
  -subj '/CN=conge.lab.invalid' -keyout /tmp/s.key -out /etc/nginx/tls/lab.crt
# ...wait for the alert, then:
sudo cp /root/lab.crt.real /etc/nginx/tls/lab.crt && sudo systemctl reload nginx

tail -20 /var/log/lab-monitor-alerts.log
lab check s6-03-monitoring-first
```

The check does all three itself, puts everything back on every exit path, and
checks a quiet period *first* — because if the log grows on its own then "a
line appeared" proves nothing about any of the three conditions.

## Prevention
A rule you have never seen fire is a rule you have no reason to believe in. Put
the three commands above in the runbook as a quarterly drill; it takes ten
minutes and it is the only thing that distinguishes monitoring from a
configuration file.

And keep the alert log even once you have a real notification channel. The
channel tells you now; the log tells you what happened at 04:00 three weeks
ago, which is the question you have when someone asks whether this has happened
before.

## What I did not know before this
That the hard half of monitoring is not the rules, it is the delivery. A rule
that evaluates correctly and notifies nowhere looks perfect through the
monitoring system's own interface — the Alerts page says `firing` and everyone
is satisfied — and is worth exactly nothing. The only test that catches it is
one that reads the destination rather than the source.
