# s6-07 — Containerise the theses app

## The goal
`nurse` — a Django API and a separately-built frontend — moves into one compose
project, same two ports, same data, with the seven challenges that touch this
app still passing afterwards.

## The three files

```bash
sudo -u postgres pg_dump -Fc nurse > /var/tmp/nurse-before-s6-07.dump
```

```dockerfile
# /opt/nurse/api/Dockerfile
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=settings_production
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt gunicorn
COPY . .
RUN useradd --system --no-create-home app && chown -R app /app
USER app
CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:8000", \
     "config.wsgi:application"]
```

```dockerfile
# /opt/nurse/web/Dockerfile — two stages, so node never ships
FROM node:20-slim AS build
WORKDIR /app
# ARG, not ENV on the running container: this value is compiled into the bundle.
ARG VITE_API_URL
ENV VITE_API_URL=${VITE_API_URL}
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

```yaml
# /opt/nurse/compose.yaml
name: nurse

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
      retries: 5
      start_period: 20s

  api:
    build: ./api
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:8000:8000"
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health/',timeout=4).status==200 else 1)\""]
      interval: 10s
      retries: 5
      start_period: 30s

  web:
    build:
      context: ./web
      args:
        # A build ARGUMENT. Under `environment:` it would arrive long after the
        # bundle was compiled and do nothing — see below.
        VITE_API_URL: https://theses.lab.invalid/api
    restart: unless-stopped
    # 3000 outside because that is what the host nginx proxies to; 80 inside
    # because that is where the container's nginx listens.
    ports:
      - "127.0.0.1:3000:80"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1/ >/dev/null || exit 1"]
      interval: 10s
      retries: 5

volumes:
  db_data:
```

```bash
cd /opt/nurse
PW="$(openssl rand -hex 24)"
cat > .env <<ENV
POSTGRES_DB=nurse
POSTGRES_USER=nurse_app
POSTGRES_PASSWORD=${PW}
DJANGO_SETTINGS_MODULE=settings_production
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
DATABASE_URL=postgres://nurse_app:${PW}@db:5432/nurse
ALLOWED_HOSTS=theses.lab.invalid,127.0.0.1,localhost
CORS_ALLOWED_ORIGINS=https://theses.lab.invalid
CSRF_TRUSTED_ORIGINS=https://theses.lab.invalid
ENV
chmod 600 .env
grep -q '^\.env$' .gitignore || echo '.env' >> .gitignore
unset PW

sudo systemctl disable --now nurse-api
sudo docker compose up -d --wait
sudo docker compose exec -T db \
  pg_restore -U nurse_app -d nurse --no-owner < /var/tmp/nurse-before-s6-07.dump

# The check the health endpoint cannot do for you:
curl -fsS "$NURSE_LIST" | head -c 200          # rows, not []

# Both lab.conf values, not just the mode.
cd ~/breakfix-lab
sed -i 's|^NURSE_MODE=.*|NURSE_MODE="compose"|' lab.conf
sed -i 's|^NURSE_ENV=.*|NURSE_ENV="/opt/nurse/.env"|' lab.conf
lab check s6-07-containerise-nurse
```

## The one that will catch you

`VITE_API_URL` under `environment:` instead of `build.args`.

| | What you see |
|---|---|
| The container | starts, stays healthy |
| The page | loads, layout perfect |
| `/api/health/` | 200 |
| The list | **empty** |

The value is compiled into the JavaScript bundle at build time. An environment
variable on the running container arrives long afterwards and changes nothing.
This is exactly the symptom s3-02 manufactures on purpose — and here you can
produce it yourself without trying.

The diagnostic is to look at what shipped, not at what is configured:

```bash
sudo docker compose exec web grep -ro 'http[^"]*api' /usr/share/nginx/html | head -3
```

## And the one that will catch you later

`NURSE_ENV` in `lab.conf` still pointing at `/etc/nurse/nurse.env`. Seven
challenges edit that file to cause faults. If the app now reads
`/opt/nurse/.env`, those challenges write to a file nothing loads — and the
symptom is a challenge that appears not to work, which sends you to debug the
lab instead of the machine. Change both values in the same edit.

## Verification
`lab check s6-07-containerise-nurse` — s6-02's shape standard against the API,
both ports on loopback, the list endpoint returning rows rather than only a
healthy `/api/health/`, `VITE_API_URL` as a build argument, `NURSE_ENV` naming a
file the project actually loads, an override file being honoured (because s5-04
needs one), `svc_restart nurse api` working, and the data surviving
`docker compose down`.

## Prevention
Write down which of your configuration values are build-time and which are
run-time, per application, in the runbook. It is a two-line note that prevents
the single most confusing class of frontend bug, and nothing in the running
system will tell you the answer — by the time the container is up, the
distinction has already been made.

## What I did not know before this
That a multi-stage build is the normal way to ship a frontend, not an
optimisation — the build stage needs node and a few hundred megabytes, and the
thing that runs needs neither. And that `docker compose config` shows build
arguments and environment variables in different places, which is what makes
the difference between them checkable at all rather than only discoverable by
loading the page.
