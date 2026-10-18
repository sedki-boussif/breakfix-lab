**The goal.** `leaves` runs as gunicorn under systemd against the host's
PostgreSQL. Move it into a compose project: a `Dockerfile` for the app, a
`compose.yaml` with its own PostgreSQL, a named volume for the data, an env
file, and healthchecks — and bring the existing data with it.

The compose project goes in `$LEAVES_DIR`, alongside the checkout.

**The work, in order, and the order is the whole difficulty:**

1. **Dump the data first**, from the host PostgreSQL, before anything else
   changes. `pg_dump` of `$LEAVES_DB_NAME`. Keep it somewhere outside
   `$LEAVES_DIR` so a careless `git clean` cannot take it.
2. **Write the `Dockerfile`.** Python base image, the application's
   requirements, gunicorn, a non-root user, and the same WSGI entry point the
   unit uses — `$LEAVES_WSGI`.
3. **Write `compose.yaml`**: the app service and a `postgres:16` service, a
   **named volume** for the database's data directory, an **env file** rather
   than values written into the compose file, and a **healthcheck on each**
   service — with the app depending on the database being healthy rather than
   merely started.
4. **Publish on loopback only**, on the same port it uses now — `127.0.0.1:
   $LEAVES_PORT`. The host nginx already proxies there and must not need
   changing. If you change the port, you have broken every other challenge
   that touches this app.
5. **Stop *and disable* the systemd unit.** Both. A unit left enabled comes
   back at the next boot, fights the container for the port, and one of them
   loses — which is s5-06 arriving by accident, months later, as a mystery.
6. **Restore the dump** into the containerised database.
7. **Flip `LEAVES_MODE` to `compose`** in `lab.conf`. `lib/svc.sh` reads it, and
   every other challenge that starts or stops this app goes through that
   setting. Until you change it, the lab is still trying to use `systemctl`.

**The standard this will be checked against:**

- `docker compose config` validates, and the project is named
  `$LEAVES_PROJECT`.
- A **named volume** holds the database's data directory — not a bind mount,
  not an anonymous volume.
- Secrets come from an **env file**; `compose.yaml` itself contains no
  password.
- **Both services have a healthcheck**, and the app waits on the database being
  healthy.
- The app answers on **`$LEAVES_URL`**, unchanged, and the host nginx was not
  touched.
- The systemd unit is **stopped and disabled**.
- `LEAVES_MODE=compose` in `lab.conf`, and the lab's own service abstraction
  works through it.
- **And the data survives destruction.** The check counts rows, runs
  `docker compose down`, brings the project back up, and counts again. The
  numbers must match, and must not be zero — a stack that comes back empty
  twice is consistent and worthless.

**What the check will not do.** It never runs `docker compose down -v`. That
removes volumes, and the difference between `down` and `down -v` is the
difference between a restart and a data loss. Know which one your own runbook
says.
