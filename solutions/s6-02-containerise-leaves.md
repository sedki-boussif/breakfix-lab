# s6-02 — Containerise the leave app

## The goal
`leaves` moves from gunicorn-under-systemd against the host PostgreSQL into a
compose project with its own database, a named volume, an env file and
healthchecks — same port, same data.

## The order, and why

```bash
# 1. The data first, before anything can change under you.
sudo -u postgres pg_dump -Fc leaves > /var/tmp/leaves-before-s6-02.dump
ls -l /var/tmp/leaves-before-s6-02.dump      # non-zero, or stop here
```

```dockerfile
# 2. /opt/leaves/Dockerfile
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
# requirements before the code, so a one-line change does not reinstall the world
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt gunicorn
COPY . .
RUN useradd --system --no-create-home app && chown -R app /app
USER app
# 0.0.0.0 inside the container, not 127.0.0.1 — the publish mapping is what
# restricts it to loopback on the host.
CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:8081", \
     "leave_management_project.wsgi:application"]
```

```yaml
# 3. /opt/leaves/compose.yaml
name: leaves

services:
  db:
    image: postgres:16
    restart: unless-stopped
    env_file: .env
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

  web:
    build: .
    restart: unless-stopped
    env_file: .env
    # The host IP written explicitly: "8081:8081" publishes everywhere, and
    # Docker's iptables rules sit in front of ufw's.
    ports:
      - "127.0.0.1:8081:8081"
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8081/etoile-formation-conge/',timeout=4).status==200 else 1)\""]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  db_data:
```

```bash
# 4. The env file: not committed, and the only place a password appears.
cd /opt/leaves
PW="$(openssl rand -hex 24)"
cat > .env <<ENV
POSTGRES_DB=leaves
POSTGRES_USER=leaves_app
POSTGRES_PASSWORD=${PW}
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
ALLOWED_HOSTS=conge.lab.invalid,127.0.0.1,localhost
DATABASE_URL=postgres://leaves_app:${PW}@db:5432/leaves
ENV
chmod 600 .env
grep -q '^\.env$' .gitignore || echo '.env' >> .gitignore
unset PW

# 5. Stop AND disable the unit, before anything else wants 8081.
sudo systemctl disable --now leaves

# 6. Up, then restore into the CONTAINER's database.
sudo docker compose up -d --wait
sudo docker compose exec -T db \
  pg_restore -U leaves_app -d leaves --no-owner < /var/tmp/leaves-before-s6-02.dump
sudo docker compose exec -T db \
  psql -U leaves_app -d leaves -c 'SELECT count(*) FROM leave_management_leaverequest'

# 7. Tell the lab.
sed -i 's|^LEAVES_MODE=.*|LEAVES_MODE="compose"|' ~/breakfix-lab/lab.conf
lab check s6-02-containerise-leaves
```

## The four mistakes worth knowing by name

| Mistake | Why it looks fine | What it costs |
|---|---|---|
| `"8081:8081"` with no host IP | the app answers, ufw still reports 8081 closed | the port is reachable from the network; Docker's iptables rules precede ufw's. This is s4-04 |
| `depends_on: [db]` with no healthcheck | works on every attempt after the first | one failed connection after every reboot, fixed by `restart:` before you see it. Nobody investigates a problem that always comes good |
| volume mounted but not declared top-level | the data does survive `down` | it is an anonymous volume, and you will not find which of a dozen hex-named volumes it is |
| `systemctl stop` without `disable` | everything works today | the unit returns at the next boot and races the container for the port |

## Verification
`lab check s6-02-containerise-leaves` — the seven shape properties, the URL
unchanged, the unit stopped *and* disabled, `LEAVES_MODE` flipped, and then the
one that matters: it counts rows, runs `docker compose down`, brings the
project back, and counts again. It requires the count to be non-zero first,
because a stack that comes back empty from empty passes a naive comparison.

## Prevention
`down` removes containers. `down -v` removes the volumes with them. Put the
difference in your runbook in those words, because the two commands differ by
two characters and by everything else.

The other habit worth keeping: `.env` in `.gitignore` before the first commit,
not after. A password removed in a later commit is still in the history, and
the only real fix at that point is rotating it.

## What I did not know before this
That `depends_on` without `condition: service_healthy` waits only for the
container to start, and that `restart: unless-stopped` then hides the
consequence completely — the stack fails once after each boot and recovers
itself. Two reasonable-looking settings combining to produce a fault that
cannot be noticed.
