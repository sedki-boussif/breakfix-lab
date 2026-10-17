Start at the layer closest to the symptom: is anything listening on the port the page is served on?
`ss -ltnp` tells you what is listening and which process owns it. Compare that with the port in lab.conf.
Nothing is listening, so the process is not running. The service is started by a wrapper script in the lab's own state directory, and it leaves a log next to itself.
The log shows the wrapper failing immediately: the interpreter it is told to exec does not exist on this machine.
Fix the interpreter path in the wrapper so it points at the python3 that is actually installed, then start it again. The check restarts it, so a hand-started process on its own will not pass.
