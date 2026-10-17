A 502 is nginx telling you it asked something else and got nothing back. nginx is working — it is reporting a failure, not causing one. So the question is what it proxies to, and whether that is running at all.
`systemctl status leaves` and `journalctl -u leaves -n 50 --no-pager` say what happened to the service. Compare with `ss -ltnp | grep 8081` to see whether anything is listening where nginx expects.
systemd reports the exit as `status=203/EXEC`. That is specifically "I could not execute the file at all" — not a Python traceback, not a port already in use, not a database problem. Nothing in the application ran.
`systemctl cat leaves` prints the unit as systemd sees it. Read the `ExecStart=` line and then run `ls -l` on the path it names.
The path in `ExecStart=` does not exist. Fix it to the interpreter that is really there, `systemctl daemon-reload`, then restart the service.
Starting gunicorn by hand will make the page work and will not pass: the check restarts the service through systemd, because a process you started by hand dies with your shell and will not come back after a reboot.
