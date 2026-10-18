# s6-07 — author notes

**Why this exists separately from s6-02.** The original plan had setup
containerise `nurse`, which assumed a Dockerfile the repository does not have:
it ships `render.yaml`, `build.sh` and `deployment/setup_vps.sh` with a
`settings_production.py`, all describing a gunicorn deployment. Writing an API
Dockerfile, a frontend build and a compose file untested, in the middle of a
first VM run, is a bad trade. The same reasoning already applied to `leaves`;
this extends it to the second repository — and `nurse` turns out to be the more
instructive of the two.

**What makes it harder, and why each part is worth the extra assertions.**

*Two services, two ports.* 8000 outside for the API, 3000 outside for the
frontend mapping to 80 inside the container. The outside/inside numbers being
different is the normal case and reads like a mistake the first time, which is
why `compose_publishes_loopback` was factored out of
`compose_shape_assertions` — nurse needs the same assertion twice and a second
copy of it would have drifted.

*A build-time variable.* `VITE_API_URL` is compiled into the bundle. In compose
that means `build.args`, and the failure mode of getting it wrong is the most
interesting thing in this challenge: set it under `environment:` and the
container starts, the page loads, the layout is perfect, `/api/health/` returns
200 — and the list is empty. That is precisely the symptom s3-02 manufactures
on purpose, reachable here entirely by accident. The check distinguishes three
states rather than two: a build arg (correct), an environment variable (the
trap, with its own message naming s3-02), and absent altogether — which may
still appear to work because a default was compiled in, and will stop the
moment the API moves.

*Seven challenges read this app's configuration.* They find the environment
file through `NURSE_ENV`. After the move the app reads the project's own env
file, and if `lab.conf` still names `/etc/nurse/nurse.env` then every challenge
that edits it writes to a file nothing loads. The symptom is the worst kind a
training lab can produce: the challenge appears broken rather than the
configuration being wrong, and the reader spends an hour debugging the lab
instead of the machine. Hence two assertions rather than one — the file exists,
*and* the compose project actually references it.

*An override file has to work.* s5-04 imposes a memory limit on this app by
writing `compose.override.yaml`. A project that does not pick one up breaks
that challenge silently. The check proves it positively, by writing an override,
asking compose what it now believes, and requiring the limit to appear — then
removing it. It skips rather than overwrites if one already exists, because the
reader's own override is worth more than the assertion.

**Why the list endpoint is asserted separately from health.** `assert_http` on
`/api/health/` and `assert_http_body` on the list are different claims, and the
gap between them is this application's characteristic failure. A check that
stopped at the health endpoint would pass a stack whose frontend points
nowhere, which is the one outcome this challenge is most likely to produce.

**The trap.** `VITE_API_URL` under `environment:`. It is the natural place to
put it, compose accepts it without complaint, and everything downstream looks
healthy. Named in the brief and again in the hints, because this is one where
being told to look is much cheaper than finding it.

**A bug of my own, worth recording.** The two `VITE_API_URL` queries were
written as `compose_q "$dir" --arg w "$web_svc" '<filter>'`, but `compose_q`
takes the filter second and passes everything after it to jq — so `--arg`
landed in the filter slot, both queries returned nothing, and the assertion
reported "neither a build arg nor an environment variable" for a correct
project. A wrong answer that happened to look like a plausible verdict, which
is the most expensive kind: it would have failed a reader who had done the work
properly, and the message would have sent them to fix something that was not
broken.

**`PROVEN=mock-compose`.** Verified through the same `docker compose config`
shim as s6-02, extended to merge `compose.override.yaml` the way real compose
does, against six projects: a correct one (twenty-five assertions), the trap,
`VITE_API_URL` absent entirely, the frontend port moved, `NURSE_ENV` left at
the systemd-era path, and `NURSE_ENV` naming a file the compose project never
loads. Not exercised: a real multi-stage build and a real Vite bundle, which is
why this is mock.
