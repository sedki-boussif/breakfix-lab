Nothing is broken, so this is a measurement problem before it is a diagnosis. Get a number: `uptime` for load average, and `curl -w '%{time_total}'` against each app so "slow" becomes a figure you can compare after the fix.
Load average against core count is the first ratio that matters. `nproc` says how many cores there are; a load average several times that means work is queued, not that anything is failing.
`top -b -n1 -o %CPU | head -20` or `ps -eo pid,comm,pcpu,etimes --sort=-pcpu | head` shows what is consuming the cores. Look at how long those processes have been running — `etimes` — against when the slowness started.
Several processes are each burning a full core under a plausible-looking name. The name means nothing: check `ls -l /proc/<pid>/exe` and `cat /proc/<pid>/cmdline` to see what is really running, and who owns them.
Kill them, then watch the load average fall — it is a decaying average, so give it a minute or two before deciding whether it worked.
Renicing them instead will make requests faster while leaving the cores busy, and the check measures both load and response time, so a partial fix shows up as a partial pass.
