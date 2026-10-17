Nothing failed loudly, so start with the one hard fact available: the age of the output. `ls -l` on the report file and `date` tell you when it last worked, and that date is what you are looking for a cause around.
The job is still scheduled — read the crontab with `crontab -l` and `cat /etc/cron.d/*` rather than assuming. So it is running and not producing, or not running at all.
Ask what cron recorded: `journalctl -u cron -S '25 days ago' | tail -40`, or `/var/log/syslog`. cron logs that it started the job, which means the job itself ran and failed.
Run the job the way cron runs it, not the way you run it: `env -i /bin/sh -c '<the command>'`. It works from your shell and fails under `env -i`, and the error names what is missing.
cron gives a job a minimal environment — `PATH=/usr/bin:/bin` and little else — and the script relies on a command that only exists on an interactive PATH. Set PATH explicitly in the crontab, or use absolute paths in the script.
Running the job by hand will refresh the file and fix nothing: your shell has the PATH the job is missing. The check runs it under `env -i` for that reason.
