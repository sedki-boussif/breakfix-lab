`Address already in use` is unambiguous and it is not about the application: something already holds the port the service wants. Before anything else, do not let him reboot — a reboot may clear it and will take the evidence with it.
`sudo ss -ltnp | grep 8081` names the process holding the port, with its pid. That is the whole diagnosis in one command.
The holder is not gunicorn and not anything the leave app started. Look at what it really is: `ls -l /proc/<pid>/exe`, `tr '\0' ' ' < /proc/<pid>/cmdline`, `ps -o ppid=,user=,etimes= -p <pid>`.
It appeared while the service was briefly down, which is the only window in which it could have taken the port. Note who owns it and how long it has been running before you kill it.
Stop the squatter, then start the service and confirm the port now belongs to it: the pid listening on 8081 should be inside the service's own cgroup.
Do not fix this by moving the leave app to a different port. It starts, nginx is still pointed at 8081, and the squatter is still there to take it again. The check requires the service to own the configured port.
