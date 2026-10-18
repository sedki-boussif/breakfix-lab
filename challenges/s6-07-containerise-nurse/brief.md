**The goal.** The same exercise as s6-02, against the harder application.
`nurse` is two things: a Django API under gunicorn, and a frontend built once
into static files that the host nginx serves. Both move into one compose
project, with their own PostgreSQL, a named volume, an env file and
healthchecks — and the seven challenges that already touch this app have to
keep passing afterwards.

The compose project goes in `$NURSE_DIR`.

**What makes this one harder than s6-02:**

1. **Two services, two ports.** The API keeps `127.0.0.1:8000` and the frontend
   keeps `127.0.0.1:3000`, because the host nginx proxies to both and must not
   need changing.
2. **`VITE_API_URL` is read at build time, not run time.** It is baked into the
   bundle. In a container that means a `build:` argument, not an environment
   variable on the running service — set it as an environment variable and the
   page will load, look perfect, and show an empty list, with the API in
   perfect health. That is exactly the shape s3-02 exploits, and here you can
   cause it by accident.
3. **The frontend is static files.** Serve the built `dist/` from a small nginx
   image. Two stages in one `Dockerfile` — build with node, copy `dist` into
   nginx — is the shape worth learning, and it keeps node out of the running
   image.
4. **Seven other challenges read this app's configuration.** They find it
   through `lab.conf`, so whatever moves has to be recorded there.

**The work:**

1. Dump `$NURSE_DB_NAME` from the host PostgreSQL first.
2. A `Dockerfile` for the API — same shape as s6-02's, with `$NURSE_WSGI` as
   the entry point and `DJANGO_SETTINGS_MODULE=settings_production`.
3. A multi-stage `Dockerfile` for the frontend, taking `VITE_API_URL` as a
   **build argument**.
4. `compose.yaml`: `api`, `web`, `db`; a named volume for the database; an env
   file; a healthcheck on each; `api` waiting on `db` being healthy.
5. Stop **and disable** `$NURSE_API_UNIT`.
6. Restore the dump into the containerised database.
7. **Update `lab.conf`**: `NURSE_MODE` to `compose`, and `NURSE_ENV` to
   wherever the environment now actually lives. Several challenges edit that
   file to cause faults; if it still points at `/etc/nurse/nurse.env` while the
   app reads the project's `.env`, those challenges will appear to do nothing.

**The standard this will be checked against** — everything s6-02 was held to,
plus:

- **Both** ports published on loopback, unchanged.
- The **API answers and the list endpoint returns rows** — not just a healthy
  `/api/health/`, which is the distinction s3-02 is built on.
- The **frontend serves**, and `$NURSE_ENV` names a file that exists and that
  the running API actually reads.
- An **override file is usable** — `compose.override.yaml` — because s5-04
  writes one to impose a memory limit, and a project that ignores overrides
  silently breaks that challenge.
- `svc_restart nurse api` brings the API back, which is the operation s3-06 and
  s5-04 both depend on.
- And the data survives `docker compose down`.
