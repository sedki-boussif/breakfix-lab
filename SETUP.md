# SETUP.md — building the lab VM

A numbered procedure that takes a fresh Ubuntu 24.04 image to three working
applications with invented data, two snapshots, and a `lab.conf` the challenges
can read. Follow it once, carefully. It teaches the ground the challenges then
break.

Everything here is fake. No real student, member of staff or patient data goes
near this VM, and no real domain or address appears in any file. All three apps
answer on invented hostnames under `.invalid`, which is reserved and can never
resolve on the public internet.

**Development machine versus lab VM.** These instructions target **Ubuntu 24.04
LTS**. If you are reading them on Parrot, or any other distribution, expect
package names, the state of `ssh.socket` and `ufw`'s defaults to differ — the
scripts in this repo follow Ubuntu 24.04, not your workstation. Never create
`/etc/breakfix-lab` on a machine you care about: it is the one thing standing
between every `break.sh` in this repo and your filesystem.

---

## 1. What you are building

| App | Runs as | Container/host port | Answers on |
| --- | --- | --- | --- |
| `stages` (stand-in) | Docker Compose, project `stages` | `127.0.0.1:8080` | `https://stages.lab.invalid/` |
| `leaves` | gunicorn under systemd | `127.0.0.1:8081` | `https://conge.lab.invalid/etoile-formation-conge/` |
| `nurse` | Docker Compose, project `nurse` | `127.0.0.1:8000` (api), `127.0.0.1:3000` (web) | `https://theses.lab.invalid/` |

One host nginx terminates TLS and proxies to all three. Every container
publishes to loopback only, so the host nginx is the only way in — which is
exactly the arrangement s4-04 asks you to prove is **not** automatic with
Docker.

**The three are deliberately not run the same way.** `leaves` starts life as
gunicorn under systemd so that s6-02 ("containerise the leave app") has real
work to do; `nurse` runs in containers so that s4-04 has a published port to
argue about. `lab.conf` records this per app:

```bash
RUN_MODE="compose"      # default
STAGES_MODE="compose"; LEAVES_MODE="systemd"; NURSE_MODE="compose"
```

---

## 2. The VM

| Requirement | Why | If your machine is small |
| --- | --- | --- |
| **Ubuntu 24.04 LTS**, server install | s4-06 turns on the `ssh.socket` socket-activation trap, which is 24.04 behaviour. `ufw` defaults and systemd 255 semantics are assumed throughout | Not negotiable. A different release changes the answers, not just the commands |
| **2 vCPU** | s5-05 asserts load average against the core count, so the core count has to be known and small enough that four spinning loops are visibly wrong. s9-02 runs a load generator beside the app | 1 vCPU breaks the load-average arithmetic in s5-05 and makes s9-02's p95 numbers meaningless. Do not go below 2 |
| **4 GB RAM minimum, 8 GB comfortable** | Postgres plus three app stacks is about 1.5 GB idle. s5-04 needs headroom to set a cgroup limit and let the OOM killer pick the API. s6-03's Prometheus and Grafana want another 700 MB | At 4 GB: run Netdata instead of Prometheus+Grafana in s6-03, and do not run a load test while the monitoring stack is up. Below 4 GB, s5-04 stops being a demonstration and becomes the VM dying |
| **40 GB primary disk** | Docker images and build caches are 6–8 GB. s5-01 fills the disk, s5-02 exhausts inodes, s5-03 holds a deleted multi-gigabyte file open — all three need room to break *and* to recover | 25 GB works if you shrink the sizes in s5-01 and s5-03, but the "under 80% used" assertions move with it and you will be editing checks |
| **A second blank disk, 10 GB, left unformatted** | s6-01: build an LVM volume group on it, move `/var/lib/docker` onto it, mount by UUID, extend it live | A loopback file is documented as a fallback in s6-01 and is **not equivalent**: it is backed by the filesystem you are supposedly moving off, so nothing is really separated and the reboot-persistence assertion proves much less |
| **Hypervisor snapshots** | s5-07 and s7-07 cannot be undone by script. `lab start` asks you to confirm you have one | No substitute. Without snapshots, skip every challenge marked `RISK=irreversible` |
| **Hypervisor console access** | s4-06 removes your SSH access on purpose; recovery is through the console | Without it, do not start s4-06. Its `break.sh` makes you type `yes-i-have-console` for this reason |
| **A bridged network adapter** | The networking challenges have to be reachable from your laptop as a separate host. NAT with port forwarding hides exactly the faults s4-01 and s4-04 are about | If you can only do NAT, s4-01 and s4-04 lose their point. Bridge it if the hypervisor allows it at all |

Leave the second disk attached but untouched: `lsblk` should show it with no
partitions and no filesystem.

---

## 3. Base install, then the `clean` snapshot

```bash
# 1. A user with your key, and no password login.
sudo adduser --disabled-password --gecos "" lab
sudo usermod -aG sudo lab
sudo install -d -m 700 -o lab -g lab /home/lab/.ssh
# paste your public key, from your laptop:
sudo -u lab tee -a /home/lab/.ssh/authorized_keys < /dev/stdin
sudo chmod 600 /home/lab/.ssh/authorized_keys
```

```bash
# 2. Harden sshd. On 24.04 the listener belongs to ssh.socket, not sshd.service:
#    changing Port in sshd_config alone does nothing. Remember this — it is the
#    trap in s4-06.
sudo sed -i -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
            -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
            -e 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' \
            /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl restart ssh
systemctl is-active ssh.socket    # this is what owns port 22
```

Open a **second** SSH session now and confirm it works before closing the first.

```bash
# 3. Firewall: deny inbound by default, allow only what the lab needs.
sudo apt update && sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
```

```bash
# 4. Infrastructure: Docker, nginx, Postgres (for leaves), and the tools the
#    challenges expect to find.
sudo apt install -y ca-certificates curl gnupg git make shellcheck jq \
                    nginx postgresql-16 python3-venv python3-pip \
                    openssl age restic
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io \
                                       docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker lab        # log out and back in for this to take effect
```

```bash
# 5. The lab marker. Nothing in this repo that touches the system will run
#    without it, and nothing can be flagged or argued into bypassing it.
echo breakfix-lab | sudo tee /etc/breakfix-lab
```

```bash
# 6. The lab itself.
git clone <your fork of this repo> ~/breakfix-lab
cd ~/breakfix-lab && cp lab.conf.example lab.conf
export PATH="$HOME/breakfix-lab/bin:$PATH"   # add to ~/.bashrc too
make lint && make selftest
```

### Take the `clean` snapshot now

Shut the VM down and snapshot it as **`clean`**.

`clean` means: Ubuntu installed, your user and key, SSH hardened, `ufw` enabled
and denying inbound, Docker and nginx and Postgres **installed**, the lab marker
present, this repo cloned — and **no application deployed, no app database, no
seeded row**. Infrastructure counts as base, not as apps.

This is what you roll back to when a challenge has gone so far wrong that
`reset.sh` is not enough, and it is the starting point for s6-05's Ansible
rebuild.

---

## 4. `LAB_LAN_IP`: find it, and know when it changes

The networking challenges have to reach the VM **the way your laptop would**.
Over loopback they prove nothing: a firewall rule that drops the app port still
answers on `127.0.0.1`, and a container published to `0.0.0.0` looks identical
to one published to loopback until you come at it from another host. That is the
whole of s4-01 and most of s4-04.

Find it on the VM:

```bash
ip -4 addr show scope global | awk '/inet /{print $2, $NF}'
```

Take the address on your real network interface — `ens18`, `enp0s3`, `eth0` or
similar. **Ignore** anything on `docker0`, a `br-*` bridge or a `veth*`: those
are Docker's own networks and are not reachable from your laptop. Put the
address in `lab.conf`:

```bash
LAB_LAN_IP="192.0.2.25"      # yours will differ; this is a documentation address
```

Then map the three invented hostnames to it, on the VM **and on your laptop**:

```
192.0.2.25   stages.lab.invalid conge.lab.invalid theses.lab.invalid
```

on the VM in `/etc/hosts`, and on your laptop in `/etc/hosts` (or
`C:\Windows\System32\drivers\etc\hosts`).

**It changes when:**

- the DHCP lease expires or the VM reboots onto a new one — fix this properly by
  reserving the address on your router or setting a static address with netplan;
- you move the laptop or VM between networks (home to office, wifi to ethernet);
- you switch the adapter between bridged and NAT, which also changes whether the
  laptop can see the VM at all;
- you add a second adapter and the first one is no longer the one that matters.

When it changes, three things need updating: `LAB_LAN_IP` in `lab.conf`, both
`/etc/hosts` files, and the certificate in s4-03 if you issued it against the
address rather than the name. A check that starts failing in all three
networking challenges at once is almost always this and not a fault.

---

## 5. `stages-lab` — the App A stand-in

**This is the largest piece of setup, and it is a real application, not a
placeholder page.** It stands in for a private hospital-internship management
app that cannot be published: its git history still holds real student files,
pending a rewrite, and a stand-in keeps this lab repo shareable. Read
`stages-lab/README.md` for what it does and does not reproduce.

What matters is that it carries the **topology** the challenges exercise: two
Docker networks with the back one `internal: true`, so the database has no route
off the host; an uploads volume owned by a non-root uid; healthchecks where
`web` refuses to start until `api` is genuinely healthy; two database roles where
the application's role has `SELECT, INSERT` on `audit_log` and nothing else; and
three configuration mistakes that stop the app starting rather than being quietly
tolerated.

```bash
# 1. Put it where lab.conf expects it.
sudo mkdir -p /opt/stages && sudo chown "$USER":"$USER" /opt/stages
cp -r ~/breakfix-lab/stages-lab/. /opt/stages/
cd /opt/stages
```

```bash
# 2. Throwaway secrets, generated here and never committed.
cp .env.example .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" .env
OWNER_PW="$(openssl rand -hex 16)"; APP_PW="$(openssl rand -hex 16)"
sed -i -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${OWNER_PW}|" \
       -e "s|^APP_DB_PASSWORD=.*|APP_DB_PASSWORD=${APP_PW}|" \
       -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+psycopg://stages_app:${APP_PW}@db:5432/stages|" \
       -e "s|^MIGRATION_DATABASE_URL=.*|MIGRATION_DATABASE_URL=postgresql+psycopg://stages_owner:${OWNER_PW}@db:5432/stages|" \
       .env
chmod 600 .env
unset OWNER_PW APP_PW
```

```bash
# 3. Build and start. web waits for api to be healthy, api waits for db.
docker compose up -d --build
docker compose ps        # all three should reach (healthy), not just Up
```

```bash
# 4. Migrate as the OWNER role. The migration also issues the grants that make
#    audit_log append-only for the application's role.
docker compose exec -T api alembic upgrade head
```

**Prove the topology, now, while you still know what you did.** These four
checks are the reason the stand-in exists:

```bash
# The database has no route off the host: nothing is published, and the back
# network is internal.
docker compose port db 5432 || echo "correct: db publishes nothing"
ss -ltn | grep -c 5432 || echo "correct: nothing on 5432 on the host"

# The app's role can append to the audit log...
docker compose exec -T db psql -U stages_app -d stages \
  -c "INSERT INTO audit_log (actor, action, detail) VALUES ('setup','check','ok')"

# ...and cannot rewrite or erase it. Both of these must fail.
docker compose exec -T db psql -U stages_app -d stages \
  -c "UPDATE audit_log SET actor='someone else'" || echo "correct: UPDATE refused"
docker compose exec -T db psql -U stages_app -d stages \
  -c "DELETE FROM audit_log" || echo "correct: DELETE refused"
```

**And prove it refuses to start when it should.** Three configuration mistakes,
each of which must kill the container rather than be tolerated:

```bash
for bad in "JWT_SECRET=change-me-before-production" "FORWARDED_ALLOW_IPS=" "DEBUG=true"; do
  echo "--- with ${bad}"
  docker compose run --rm -e "${bad}" api \
    python -c "from app.config import load; load()" 2>&1 | tail -3
done
```

Each one must print a refusal naming the variable. If any of them starts
happily, the check is not working and several challenges lose their teeth.

The stand-in now answers on `127.0.0.1:8080`:

```bash
curl -fsS http://127.0.0.1:8080/api/health/ && echo
curl -fsS http://127.0.0.1:8080/ | head -5
```

### Pointing at the real app later

Change `STAGES_DIR` in `lab.conf`. Nothing in any challenge hard-codes the path.
If the real app's compose services are not called `db`, `api` and `web`, update
`STAGES_WEB`, `STAGES_API` and `DB_SERVICE` to match and the challenges follow.

---

## 6. `leaves` — gunicorn under systemd

The public leave-management repository, at tag `v3.0`. It runs **without
Docker**, deliberately: s6-02 asks you to containerise it, and you cannot
containerise what is already in a container.

```bash
sudo mkdir -p /opt/leaves && sudo chown "$USER":"$USER" /opt/leaves
git clone --branch v3.0 <the leaves repository> /opt/leaves
cd /opt/leaves
python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt gunicorn
```

```bash
# Its own database, on the host Postgres.
LEAVES_PW="$(openssl rand -hex 16)"
sudo -u postgres createuser leaves_app
sudo -u postgres createdb -O leaves_app leaves
sudo -u postgres psql -c "ALTER ROLE leaves_app WITH PASSWORD '${LEAVES_PW}'"
```

```bash
# The environment file. SECRET_KEY has no default in this app: remove it and the
# app dies at import rather than starting insecure. That is s3-03, so know where
# this file lives.
sudo install -d -m 750 /etc/leaves
sudo tee /etc/leaves/leaves.env > /dev/null <<EOF
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
ALLOWED_HOSTS=conge.lab.invalid,127.0.0.1,localhost
DATABASE_URL=postgres://leaves_app:${LEAVES_PW}@127.0.0.1:5432/leaves
EOF
sudo chmod 640 /etc/leaves/leaves.env
unset LEAVES_PW
```

```bash
# Migrations, static files and the rh_admin seed the repo ships.
set -a; . /etc/leaves/leaves.env; set +a
./.venv/bin/python manage.py migrate
./.venv/bin/python manage.py collectstatic --no-input
bash build.sh    # or just the rh_admin seeding step from it
```

```bash
# The unit. Note the ExecStart path: s3-01 corrupts exactly this line.
sudo tee /etc/systemd/system/leaves.service > /dev/null <<'EOF'
[Unit]
Description=leaves (staff leave requests)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/leaves
EnvironmentFile=/etc/leaves/leaves.env
ExecStart=/opt/leaves/.venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8081 \
          --access-logfile /var/log/leaves/access.log \
          --error-logfile /var/log/leaves/error.log \
          leave_management_project.wsgi:application
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sudo install -d -o www-data -g www-data /var/log/leaves
sudo chown -R www-data:www-data /opt/leaves
sudo systemctl daemon-reload && sudo systemctl enable --now leaves
systemctl is-active leaves
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/etoile-formation-conge/
```

**The layout, pinned.** At `v3.0` the Django project package is
`leave_management_project` and the application is `leave_management`, so the
WSGI entry point is `leave_management_project.wsgi:application` — note that it
is *not* `config.wsgi`, which is what `nurse` uses. Models live in
`leave_management/models.py`: `LeaveRequest`, `Holiday`, and a custom user model
with a `role` field, which is what `build.sh` sets to `HR` when it seeds
`rh_admin`. Migrations run to `0004_leaverequest_ceo_decision_at_and_more`.

Verify that against the repo you actually cloned before trusting it — a moved
tag changes all of it:

```bash
ls /opt/leaves/*/wsgi.py                        # the project package
./.venv/bin/python manage.py showmigrations leave_management | tail -3
```

Everything is mounted under `/etoile-formation-conge/`, `admin/` and `login/`
included, so a bare `/` returning 404 is correct and not a fault.

`/var/log/leaves/access.log` is what s2-04 writes a logrotate rule for, so do
not point it at the journal instead.

---

## 7. `nurse` — containers, and a build-time API URL

The public thesis-catalogue repository. It runs in containers, so that s4-04 has
a published port to argue about.

```bash
sudo mkdir -p /opt/nurse && sudo chown "$USER":"$USER" /opt/nurse
git clone <the nurse repository> /opt/nurse
cd /opt/nurse
```

If the repo ships a `compose.yaml`, use it. If not, this is the minimum the lab
expects — api on 8000, web on 3000, both on loopback:

```yaml
name: nurse
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_DB: nurse
      POSTGRES_USER: nurse_app
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes: [db_data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nurse_app -d nurse"]
      interval: 10s
      retries: 5
  api:
    build: .
    env_file: .env
    ports: ["127.0.0.1:8000:8000"]
    depends_on:
      db: {condition: service_healthy}
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/api/health/')\""]
      interval: 10s
      retries: 5
  web:
    build:
      context: ./frontend
      args:
        VITE_API_URL: https://theses.lab.invalid/api
    ports: ["127.0.0.1:3000:80"]
volumes:
  db_data:
```

```bash
# Secrets. This app has two real weaknesses, kept on purpose as material for
# s4-07: SECRET_KEY falls back to a hard-coded insecure default, and DEBUG
# defaults to True when unset. Set both explicitly here, and fix the code in
# s4-07 so that neither fallback exists.
cat > .env <<EOF
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
DB_PASSWORD=$(openssl rand -hex 16)
ALLOWED_HOSTS=theses.lab.invalid,127.0.0.1,localhost
CORS_ALLOWED_ORIGINS=https://theses.lab.invalid
CSRF_TRUSTED_ORIGINS=https://theses.lab.invalid
EOF
chmod 600 .env
docker compose up -d --build
docker compose exec -T api python manage.py migrate
# This repo ships its own command for the staff account; use it rather than
# createsuperuser, so the role and defaults it sets are the ones you get.
docker compose exec -T api python manage.py create_default_superuser
```

**The layout, pinned.** The Django project package is `config`, so
`config.wsgi:application` is correct here (unlike `leaves`). The application is
`theses`, with models in `theses/models.py`: `Thesis` and
`ThesisStatusHistory`. `Thesis.numero` carries a uniqueness constraint, which
matters when seeding — `seed.sh` generates it from a counter for exactly this
reason. Migrations run to
`0003_thesisstatushistory_thesis_disponible_and_more`. Two management commands
already exist: `import_excel` and `create_default_superuser`.

**The repo root is messy.** Duplicate `.jsx` and `.py` files sit at the top
level alongside the real `frontend/src/` and `theses/`. **The canonical copies
are the ones inside those directories** — edit `theses/models.py`, not a
`models.py` at the root, and `frontend/src/App.jsx`, not a root-level `App.jsx`.
s4-07 patches this repo for real, so know which file you are editing before you
start, or you will fix a copy nothing imports.

```bash
# Verify before trusting any of the above:
docker compose exec -T api ls config/wsgi.py theses/models.py
docker compose exec -T api python manage.py showmigrations theses | tail -3
docker compose exec -T api python manage.py help | grep -A3 '\[theses\]'
```

**`VITE_API_URL` is read at build time**, not at run time. A wrong value is
baked into the JavaScript bundle and shows up only in the browser — the API will
be perfectly healthy and the page still empty. Remember this shape: it is how
s3-02 can look like a frontend fault when it is not.

```bash
curl -fsS http://127.0.0.1:8000/api/health/ && echo
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
```

---

## 8. One host nginx in front of all three

Name-based virtual hosts, so each app gets a clean root and TLS can be issued
per name. All three upstreams are on loopback.

```bash
sudo tee /etc/nginx/sites-available/lab > /dev/null <<'EOF'
# stages
server {
    listen 80;
    server_name stages.lab.invalid;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
# leaves — everything lives under the prefix, including admin/ and login/
server {
    listen 80;
    server_name conge.lab.invalid;
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
# nurse — api and the built bundle are separate upstreams
server {
    listen 80;
    server_name theses.lab.invalid;
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 16m;
    }
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/lab /etc/nginx/sites-enabled/lab
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

TLS comes later: s4-03 is about a certificate that has expired, so issue a
self-signed certificate with a sane lifetime now (certbot cannot validate a
`.invalid` name, which is the point of using one):

```bash
sudo mkdir -p /etc/nginx/tls
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/tls/lab.key -out /etc/nginx/tls/lab.crt \
  -subj "/CN=stages.lab.invalid" \
  -addext "subjectAltName=DNS:stages.lab.invalid,DNS:conge.lab.invalid,DNS:theses.lab.invalid"
sudo chmod 600 /etc/nginx/tls/lab.key
```

Then add `listen 443 ssl;` with `ssl_certificate /etc/nginx/tls/lab.crt;` and
`ssl_certificate_key /etc/nginx/tls/lab.key;` to each server block, and reload.
Record in `lab.conf` where the certificate lives so s4-03 can find it.

From your **laptop**, not the VM:

```bash
curl -kfsS -o /dev/null -w '%{http_code}\n' https://stages.lab.invalid/
curl -kfsS -o /dev/null -w '%{http_code}\n' https://conge.lab.invalid/etoile-formation-conge/
curl -kfsS -o /dev/null -w '%{http_code}\n' https://theses.lab.invalid/
```

If those answer from the laptop and `ufw status` still shows default deny
inbound, the arrangement is right.

---

## 9. Seed the data — and why these numbers

```bash
cd ~/breakfix-lab
bash lib/seed.sh all
```

The volumes live in `lab.conf`. They are not arbitrary:

| Setting | Default | Why that number |
| --- | --- | --- |
| `SEED_PLACEMENTS` | **60,000** | This is the one that matters. s9-07 drops the index on `(ward, started_on)` and asks you to notice. (s9-02 is now the worker-pool fault instead: an 11 ms query difference cannot be seen through a load generator sharing two cores, but a starved pool is unmistakable.) At a few hundred rows a sequential scan and an index lookup are both under a millisecond — inside measurement noise, so the "fault" would be invisible and the challenge dishonest. At 60,000 rows the gap is real and measured: on the machine this was developed on, the filtered count runs in **3.1 ms** on a bitmap index scan and **14.7 ms** on a sequential scan. That 4.7× ratio is plain in `EXPLAIN (ANALYZE)`, which is how s9-07 measures it — but it is only about 11 ms of wall clock, so do **not** expect to see it through a load generator competing for the same two cores. 60,000 also seeds in about six seconds and fits comfortably in a backup you will restore over and over |
| `SEED_AUDIT` | **5,000** | s9-03 measures a *growth rate*, and a rate needs a baseline to subtract. Starting from an empty table makes any growth look infinite and nothing look like a trend. 5,000 rows is a credible few months of history to measure against |
| `SEED_TRAINEES` | 400 | Enough that `placements` fans out across many parents, so the join is not degenerate and the planner's choices are realistic |
| `SEED_THESES` | 3,000 | Enough for the catalogue's search and pagination to behave like a catalogue rather than a list, and for s3-02's "the list endpoint returns rows" to mean something |
| `SEED_LEAVE_REQUESTS` | 60 | Volume is not the point here: the HR-then-CEO approval queue just needs to be non-trivial |

**Shrinking them.** Everything except `SEED_PLACEMENTS` can be cut freely. Below
about 6,000 placements, s9-02 stops being measurable and you should skip it
rather than pretend — a challenge whose fault hides inside the error bars
teaches the wrong lesson.

**Check the gap on your own VM before trusting s9-07**, because the numbers above
came from a development workstation and yours will be slower:

```bash
cd /opt/stages
Q="SELECT count(*) FROM placements WHERE ward='Ward Echo' AND started_on > CURRENT_DATE - 200"
docker compose exec -T db psql -U stages_owner -d stages -c "EXPLAIN (ANALYZE) $Q" | tail -2
docker compose exec -T db psql -U stages_owner -d stages   -c "DROP INDEX ix_placements_ward_started" -c "ANALYZE placements"
docker compose exec -T db psql -U stages_owner -d stages -c "EXPLAIN (ANALYZE) $Q" | tail -2
docker compose exec -T db psql -U stages_owner -d stages   -c "CREATE INDEX ix_placements_ward_started ON placements (ward, started_on)"   -c "ANALYZE placements"
```

You want to see `Bitmap Index Scan` become `Seq Scan`, and the execution time
rise by at least 4×. If it does not, raise `SEED_PLACEMENTS` to 200,000 and
re-seed — the cost is a slower seed and a bigger backup, not a worse lab.
s9-07 measures with `EXPLAIN (ANALYZE)` and query time rather than wall clock
under load, which is why a 4–5× ratio is enough signal for it.

**For s9-03 you also need a log baseline.** `/var/log/leaves/access.log` and the
`audit_log` table are what grow. Record their size now, because "it gets worse
over hours" is a claim about a rate and you cannot compute one from a single
reading:

```bash
{ date -Is; ls -l /var/log/leaves/access.log; } | tee -a ~/lab-baseline.txt
```

**The bulk seed targets are pinned**: `LeaveRequest` for `leaves` and `Thesis`
for `nurse`, both set in `lab.conf`. `seed.sh` seeds `stages` precisely because
the lab owns that schema; for the other two it asks Django for the named model,
preferring an exact name match so a hint of `Thesis` cannot land on
`ThesisStatusHistory`, and fills remaining fields by type. If a tag has moved
and the model is not there, it prints every model it found and stops rather than
guessing — change `LEAVES_SEED_MODEL` or `NURSE_SEED_MODEL` and run it again.
Confirm both now, while the repos are fresh in your mind, rather than during a
timed challenge.

---

## 10. Verify, then take the `deployed` snapshot

```bash
curl -fsS http://127.0.0.1:8080/api/health/                                   # stages api
curl -fsS -o /dev/null -w 'stages  %{http_code}\n' http://127.0.0.1:8080/
curl -fsS -o /dev/null -w 'leaves  %{http_code}\n' http://127.0.0.1:8081/etoile-formation-conge/
curl -fsS -o /dev/null -w 'nurse   %{http_code}\n' http://127.0.0.1:3000/
curl -fsS http://127.0.0.1:8000/api/health/                                   # nurse api
curl -fsS http://127.0.0.1:8080/api/placements/count/                         # should be ~60000
systemctl is-active nginx leaves postgresql
docker compose -p stages ps; docker compose -p nurse ps
```

All three answer, `placements` holds the seeded volume, every container reports
`(healthy)`. Now:

```bash
cd ~/breakfix-lab && lab list      # the catalogue, nothing passed yet
```

Shut down and snapshot as **`deployed`**.

`deployed` means: everything in `clean`, plus all three applications running and
seeded, the host nginx in front of them, TLS in place, and `lab.conf` filled in
with your real `LAB_LAN_IP`. This is the snapshot almost every challenge expects,
and the one you roll back to after an irreversible break.

---

## 11. Which snapshot each challenge expects

| Challenges | Snapshot | Notes |
| --- | --- | --- |
| `s0-00-smoke` | `clean` | Throwaway. Needs no app; works on either snapshot |
| `s2-01`, `s2-03`, `s2-04` | `deployed` | s2-03 curls all three apps; s2-04 rotates the leaves log |
| `s2-02` | `clean` | System only — `sysinfo.sh` does not care whether apps are running |
| `s3-01` … `s3-07` | `deployed` | All seven are incidents against running apps. s3-07 is system-only but there is no reason to leave `deployed` for it |
| `s4-01` … `s4-05`, `s4-07` | `deployed` | s4-01 and s4-04 need `LAB_LAN_IP` and your laptop. s4-03 needs the certificate from section 8 |
| **`s4-06`** | `deployed` | **Snapshot *and* hypervisor console required.** `RISK=irreversible`: you will lose SSH on purpose. `break.sh` makes you type `yes-i-have-console` |
| `s5-01` … `s5-06`, `s5-08`, `s5-09` | `deployed` | Reversible. `reset.sh` undoes each one |
| **`s5-07`** | `deployed` | **Snapshot required.** `RISK=irreversible`: a bad UUID in `/etc/fstab` boots the VM to emergency mode. Two-phase check — `check.sh --arm` before the reboot, `check.sh` after |
| `s6-01` … `s6-04`, `s6-06` | `deployed` | s6-01 needs the second disk from section 2, and the apps must keep serving throughout |
| `s6-05` | `clean` | Ansible rebuilds from near-bare. The final proof — "a fresh VM reaches a working state from the playbook alone" — needs a **new VM**, not a snapshot |
| `s7-01` … `s7-06` | `deployed` | "Off-VM" is always simulated locally: a second container, a separate mount, or a second VM. Never a real cloud account |
| **`s7-07`** | `deployed` | **Snapshot required.** `RISK=irreversible`: the fake uploads are scrambled and local backups removed |
| `s8-01`, `s8-02`, `s8-03` | neither | These start from a **bare Ubuntu 24.04 image**. s8-02 deletes the VM on purpose; rebuilding from Git and backups alone is the exercise. Keep `deployed` so you have something to compare against |
| `s9-01` … `s9-07` | `deployed` | Including the empty round in s9-06. `lab chaos` draws only from reversible level 2–4 challenges, so it will never fire s4-06, s5-07 or s7-07 |

Two snapshots, then. Most of the time you want `deployed`. Reach for `clean`
when a challenge has gone further wrong than `reset.sh` can follow, and when a
rebuild mission wants to start before the apps existed.
