Four messages from the watchdog, overnight. No human has looked at them yet.

```
[03:02:11] lab-watch: nurse-api UNREACHABLE (http://127.0.0.1:8000/api/health/ → 000)
[03:02:11] lab-watch: nurse-web UNREACHABLE (http://127.0.0.1:3000/ → 000)
[03:07:11] lab-watch: nurse-api UNREACHABLE (http://127.0.0.1:8000/api/health/ → 000)
[03:07:11] lab-watch: nurse-web UNREACHABLE (http://127.0.0.1:3000/ → 000)
```

```
[02:58:40] system: scheduled reboot for unattended-upgrades completed, uptime 0m
```

`stages` and `leaves` reported nothing. No recovery message has arrived for
either nurse check.

**This challenge involves a reboot.** `check.sh --arm` records the state it will
check against; reboot the VM; then run `lab check s3-06-works-until-reboot` to
assert the app came back on its own.
