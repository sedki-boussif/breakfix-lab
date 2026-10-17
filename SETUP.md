# SETUP.md — building the lab VM

A numbered procedure that takes a fresh Ubuntu 24.04 image to three working
applications with invented data, two snapshots, and a `lab.conf` the challenges
can read. Follow it once, carefully. It teaches the ground the challenges then
break.

Everything here is fake. No real student, member of staff or patient data goes
near this VM, and no real domain or address appears in any file. All three apps
answer on invented hostnames under `.invalid`, which is reserved and can never
resolve on the public internet.

**Where this file and a repository disagree, the repository wins.** `leaves` and
`nurse` are not mine: each ships its own deployment documentation, and §6 and §7
below are my *summary* of it, written without the repositories in front of me.
Read theirs first, reconcile, and follow theirs:

| App | Read these, in the repo, before starting its section |
| --- | --- |
| `leaves` | `README_VPS.md`, `README_POSTGRESQL.md` |
| `nurse` | `deployment/QUICK_START.md`, `deployment/setup_vps.sh`, `deployment/CONFIG_TEMPLATES.md`, `settings_production.py` |

Where they contradict this file, **write the contradiction down and report it**
rather than picking whichever looks more plausible. A guess that happens to work
is worse than a disagreement you can see, because it survives into every
challenge built on top of it.

**Development machine versus lab VM.** These instructions target **Ubuntu 24.04
LTS**. If you are reading them on Parrot, or any other distribution, expect
package names, the state of `ssh.socket` and `ufw`'s defaults to differ — the
scripts in this repo follow Ubuntu 24.04, not your workstation. Never create
`/etc/breakfix-lab` on a machine you care about: it is the one thing standing
between every `break.sh` in this repo and your filesystem.

---

## 1. What you are building

| App | Runs as | Host port | Answers on |
| --- | --- | --- | --- |
| `stages` (stand-in) | Docker Compose, project `stages` | `127.0.0.1:8080` | `https://stages.lab.invalid/` |
| `leaves` | gunicorn under systemd | `127.0.0.1:8081` | `https://conge.lab.invalid/etoile-formation-conge/` |
| `nurse` | gunicorn under systemd, built frontend served by host nginx | `127.0.0.1:8000` (api), `127.0.0.1:3000` (frontend) | `https://theses.lab.invalid/` |

One host nginx terminates TLS and proxies to all three.

**Only `stages` is containerised, and that is deliberate.** It is the stand-in
written in this repository, so it has Dockerfiles and a compose file that are
known to work. Neither public repository ships either: `leaves` has
`render.yaml` and `README_VPS.md`, `nurse` has `render.yaml`, `build.sh` and
`deployment/setup_vps.sh` with a `settings_production.py` — both are gunicorn
deployments, and both of their own deployment documents assume exactly that.

Writing a Dockerfile for an API, another for a frontend, and a compose file to
join them — untested, in the middle of a first run — is a bad trade. So:

- **`stages` is the app s4-04 uses** ("Docker goes around the firewall"), being
  the only one with genuinely published container ports.
- **Containerising the other two is a graded mission**: s6-02 for `leaves`,
  s6-07 for `nurse`. Learning to containerise an application is worth doing as
  an exercise with a check on it, rather than having setup do it invisibly.

`lab.conf` records the per-app mode, and `lib/svc.sh` resolves it per app, so a
challenge can be talking to compose and to systemd in the same script:

```bash
RUN_MODE="compose"      # the default, for anything without its own mode
STAGES_MODE="compose"; LEAVES_MODE="systemd"; NURSE_MODE="systemd"
```

When you finish s6-02 or s6-07, change that app's mode and the challenges follow.

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

**Which user you are, for the whole of the rest of this file.** The Ubuntu
installer already made you an account. Everything below runs as **that account**
— not as a new `lab` user, and not as root. Wherever this file says `$USER` it
means the account you are logged in as, and the `docker` group membership in
step 4 is granted to that account. If you would rather use a dedicated `lab`
account, create it now, add your key, log in as it, and do everything from
there; mixing the two is what breaks step 5, because only one of them will be in
the `docker` group.

```bash
# 0. Settle it, and keep the answer in front of you.
whoami; echo "HOME=$HOME"
```

```bash
# 1. Your key, if it is not already there from the install.
#    This command waits for you to paste and then press Ctrl-D. It is not hung.
install -d -m 700 "$HOME/.ssh"
cat >> "$HOME/.ssh/authorized_keys"      # paste the public key, then Ctrl-D
chmod 600 "$HOME/.ssh/authorized_keys"
# Verify: the key is there and is one line per key.
wc -l "$HOME/.ssh/authorized_keys"
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

# VERIFY, and do not skip this. Ubuntu includes /etc/ssh/sshd_config.d/*.conf
# from the TOP of sshd_config, and the first value wins — so a cloud-image
# drop-in saying "PasswordAuthentication yes" silently beats the edit above.
# This prints what sshd will actually do:
sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication)'
# All three must read: no / no / no. If any says yes, find the override:
grep -rn -E 'PasswordAuthentication|PermitRootLogin' /etc/ssh/sshd_config.d/ 2>/dev/null
systemctl is-active ssh.socket    # this is what owns port 22
```

Open a **second** SSH session now and confirm it works before closing the first.
If you cannot, you still have the first session: undo the change rather than
rebooting.

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
                    openssl age restic \
                    psmisc lsof e2fsprogs util-linux cron
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io \
                                       docker-buildx-plugin docker-compose-plugin
# The account YOU are logged in as, not a hypothetical "lab" user.
sudo usermod -aG docker "$USER"
```

**Log out and log back in now.** Group membership is read at login, so until you
do, every `docker` command in sections 5 and 7 fails with a permission error on
`/var/run/docker.sock`. Then verify all four, before going any further:

```bash
id -nG | tr ' ' '\n' | grep -qx docker && echo "docker group: yes" || echo "docker group: NO — log out and in"
docker version --format '{{.Server.Version}}'     # talks to the daemon as you
docker compose version
systemctl is-active docker nginx postgresql
```

`nginx` and `postgresql` should both be `active` — they start on install. If
`nginx` is not, `sudo systemctl enable --now nginx` before section 8.

```bash
# 5. The lab marker. Nothing in this repo that touches the system will run
#    without it, and nothing can be flagged or argued into bypassing it.
echo breakfix-lab | sudo tee /etc/breakfix-lab
# Verify: exactly this, and nothing else. lab_guard compares it strictly.
cat -A /etc/breakfix-lab        # must read: breakfix-lab$
```

```bash
# 6. The lab itself.
# SUBSTITUTE the URL: this is one of three placeholders in this file that will
# not work copy-pasted (the other two are the leaves and nurse repositories).
git clone https://github.com/<you>/breakfix-lab.git ~/breakfix-lab
cd ~/breakfix-lab && cp lab.conf.example lab.conf
echo 'export PATH="$HOME/breakfix-lab/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/breakfix-lab/bin:$PATH"
make lint && make selftest
# Verify: both must end in a success line, and `lab list` must print the table.
lab list | head -3
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

On the VM, with the address you just found:

```bash
LAN_IP="$(ip -4 addr show scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"
echo "using ${LAN_IP}"       # sanity-check it is the one you expect
printf '%s   stages.lab.invalid conge.lab.invalid theses.lab.invalid\n' "$LAN_IP" |
  sudo tee -a /etc/hosts
sed -i "s|^LAB_LAN_IP=.*|LAB_LAN_IP=\"${LAN_IP}\"|" ~/breakfix-lab/lab.conf
# Verify both:
getent hosts stages.lab.invalid conge.lab.invalid theses.lab.invalid
grep LAB_LAN_IP ~/breakfix-lab/lab.conf
```

On your **laptop**, add the same line by hand to `/etc/hosts` (or
`C:\Windows\System32\drivers\etc\hosts`), then prove the laptop can reach
the VM at all before you build anything on it:

```bash
# from the laptop
ping -c1 stages.lab.invalid
nc -vz stages.lab.invalid 22        # SSH is the only port open yet
```

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
#    This is the slowest step in the file: it downloads Python wheels and an
#    npm tree, so it needs working internet and takes several minutes on a
#    2 vCPU VM. If your VM has no outbound access, it fails here and nothing
#    after this point will work.
#    --wait blocks until the healthchecks pass, instead of reporting "starting".
docker compose up -d --build --wait
docker compose ps        # all three must read (healthy), not Up and not starting
```

If `--wait` times out, read the logs of whichever service is not healthy before
retrying: `docker compose logs api --tail 50` (or `web`, or `db`). A `web` that
never becomes healthy is almost always the npm build; an `api` that never
becomes healthy is almost always `.env`.

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
#
# /etc/leaves/leaves.env is mode 640 root:root, so you CANNOT source it as
# yourself — `. /etc/leaves/leaves.env` returns "Permission denied". Run the
# management commands as root with the file loaded, which is also how systemd
# will run the service:
sudo bash -c 'set -a; . /etc/leaves/leaves.env; set +a
  cd /opt/leaves
  ./.venv/bin/python manage.py migrate
  ./.venv/bin/python manage.py collectstatic --no-input'
```

```bash
# The rh_admin account. build.sh does pip install, collectstatic, migrate and
# then the seed — the first three you have just done, so read it and run only
# the seeding part. If it is a single block you cannot separate, running the
# whole thing again is harmless but slow:
sed -n '1,40p' /opt/leaves/build.sh      # read it before you run it
sudo bash -c 'set -a; . /etc/leaves/leaves.env; set +a; cd /opt/leaves && bash build.sh'
# Verify: the account exists with the HR role.
sudo bash -c 'set -a; . /etc/leaves/leaves.env; set +a
  cd /opt/leaves
  ./.venv/bin/python manage.py shell -c "
from django.contrib.auth import get_user_model
u = get_user_model().objects.filter(username=\"rh_admin\").first()
print(u, getattr(u, \"role\", None))"'
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

## 7. `nurse` — gunicorn under systemd, and a build-time API URL

The public thesis-catalogue repository. Like `leaves`, it runs **without
Docker**: its own `deployment/` directory describes a gunicorn deployment, and
containerising it is s6-07's job rather than setup's.

**Read the repository's own deployment documents first**, and follow them where
they differ from what is below:

```bash
sudo mkdir -p /opt/nurse && sudo chown "$USER":"$USER" /opt/nurse
# SUBSTITUTE the URL.
git clone https://github.com/<you>/nurse.git /opt/nurse
cd /opt/nurse
ls -1 deployment/ ; ls -1 render.yaml build.sh settings_production.py 2>&1
sed -n '1,80p' deployment/QUICK_START.md
sed -n '1,120p' deployment/setup_vps.sh        # read it; do not run it blind
sed -n '1,80p' deployment/CONFIG_TEMPLATES.md
```

`setup_vps.sh` very likely does most of what follows — a virtualenv, a database,
an environment file, a unit, and an nginx block. **Prefer it to the steps below**
where they overlap, and treat the rest of this section as the shape the lab
expects the result to have: api on `127.0.0.1:8000`, built frontend on
`127.0.0.1:3000`, configuration in a file systemd loads. Note every place you
had to deviate.

```bash
# The virtualenv and dependencies.
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt gunicorn
```

```bash
# Its own database, on the host Postgres.
NURSE_PW="$(openssl rand -hex 16)"
sudo -u postgres createuser nurse_app
sudo -u postgres createdb -O nurse_app nurse
sudo -u postgres psql -c "ALTER ROLE nurse_app WITH PASSWORD '${NURSE_PW}'"
```

```bash
# The environment file. Reconcile these names with CONFIG_TEMPLATES.md and
# settings_production.py before trusting them — that file is the authority on
# what this app reads.
#
# This app has two real weaknesses, kept on purpose as material for s4-07:
# SECRET_KEY falls back to a hard-coded insecure default, and DEBUG defaults to
# True when unset. Both are set explicitly here; s4-07 removes the fallbacks.
sudo install -d -m 750 /etc/nurse
sudo tee /etc/nurse/nurse.env > /dev/null <<EOF
DJANGO_SETTINGS_MODULE=settings_production
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
DATABASE_URL=postgres://nurse_app:${NURSE_PW}@127.0.0.1:5432/nurse
ALLOWED_HOSTS=theses.lab.invalid,127.0.0.1,localhost
CORS_ALLOWED_ORIGINS=https://theses.lab.invalid
CSRF_TRUSTED_ORIGINS=https://theses.lab.invalid
EOF
sudo chmod 640 /etc/nurse/nurse.env
unset NURSE_PW
```

```bash
# Migrations, static files, and the staff account the repo ships a command for.
# As root with the env file loaded, because it is root-only — same as leaves.
sudo bash -c 'set -a; . /etc/nurse/nurse.env; set +a
  cd /opt/nurse
  ./.venv/bin/python manage.py migrate
  ./.venv/bin/python manage.py collectstatic --no-input
  ./.venv/bin/python manage.py create_default_superuser'
```

```bash
# The API unit. s5-04 adds a MemoryMax drop-in to this unit, and s3-06 disables
# it, so this is the file those two challenges act on.
sudo tee /etc/systemd/system/nurse-api.service > /dev/null <<'EOF'
[Unit]
Description=nurse (theses catalogue API)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/nurse
EnvironmentFile=/etc/nurse/nurse.env
ExecStart=/opt/nurse/.venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 \
          --access-logfile /var/log/nurse/access.log \
          --error-logfile /var/log/nurse/error.log \
          config.wsgi:application
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sudo install -d -o www-data -g www-data /var/log/nurse
sudo chown -R www-data:www-data /opt/nurse
sudo systemctl daemon-reload && sudo systemctl enable --now nurse-api
systemctl is-active nurse-api
curl -fsS http://127.0.0.1:8000/api/health/ ; echo
```

```bash
# The frontend: built once, then served as static files by the host nginx.
#
# VITE_API_URL is read at BUILD time, not at run time. A wrong value is baked
# into the bundle and shows up only in the browser — the API will be perfectly
# healthy and the page still empty. That is the shape s3-02 exploits.
cd /opt/nurse/frontend
sudo chown -R "$USER":"$USER" /opt/nurse/frontend
VITE_API_URL=https://theses.lab.invalid/api npm ci
VITE_API_URL=https://theses.lab.invalid/api npm run build
ls -la dist/index.html            # must exist; this is what nginx serves
grep -ro 'theses.lab.invalid' dist/assets/ | head -1   # proof the value was baked in
```

If `npm` is not installed: `sudo apt install -y nodejs npm`, or use the
repository's own instructions if it pins a Node version.

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
ls /opt/nurse/config/wsgi.py /opt/nurse/theses/models.py
sudo bash -c 'set -a; . /etc/nurse/nurse.env; set +a
  cd /opt/nurse && ./.venv/bin/python manage.py showmigrations theses | tail -3'
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
# nurse — the api is a gunicorn upstream; the frontend is static files.
# The 127.0.0.1:3000 block exists so that "the frontend" has a port of its own,
# which is what lab.conf's NURSE_WEB names and what the challenges curl.
server {
    listen 127.0.0.1:3000;
    server_name _;
    root /opt/nurse/frontend/dist;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
}
server {
    listen 80;
    server_name theses.lab.invalid;
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 16m;
    }
    location / {
        root /opt/nurse/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/lab /etc/nginx/sites-enabled/lab
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx
# Verify: the config is valid, nginx is up, and it answers on the vhost names.
systemctl is-active nginx
for h in stages.lab.invalid conge.lab.invalid theses.lab.invalid; do
  printf '%-22s %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $h" http://127.0.0.1/)"
done
```

All three should answer something other than `000`. A `502` here is expected
until the app behind that name is up; `000` means nginx is not listening.

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

Now put TLS on all three server blocks. This was prose in an earlier draft and
had to be hand-edited three times, which is how a verification step ends up
testing something nobody did — so it is a command:

```bash
# Add the TLS listener to every vhost that has a plain `listen 80;`. This
# deliberately does not match the `listen 127.0.0.1:3000;` block, which is an
# internal upstream and has no business terminating TLS.
sudo sed -i 's|^    listen 80;|    listen 80;\n    listen 443 ssl;\n    ssl_certificate /etc/nginx/tls/lab.crt;\n    ssl_certificate_key /etc/nginx/tls/lab.key;|' \
  /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
# Verify: three listeners on 443, and the certificate's names and dates.
grep -c 'listen 443 ssl;' /etc/nginx/sites-available/lab     # must print 3
openssl x509 -in /etc/nginx/tls/lab.crt -noout -subject -enddate -ext subjectAltName
```

```bash
# And record where it lives, so s4-03 can find it.
sed -i -e 's|^TLS_CERT=.*|TLS_CERT="/etc/nginx/tls/lab.crt"|' \
       -e 's|^TLS_KEY=.*|TLS_KEY="/etc/nginx/tls/lab.key"|' ~/breakfix-lab/lab.conf
grep ^TLS_ ~/breakfix-lab/lab.conf
```

From your **laptop**, not the VM — this is the first time anything has been
tested from outside, and it is testing three things at once: the laptop's
`/etc/hosts`, the VM's firewall, and nginx:

```bash
curl -kfsS -o /dev/null -w 'stages %{http_code}\n' https://stages.lab.invalid/
curl -kfsS -o /dev/null -w 'leaves %{http_code}\n' https://conge.lab.invalid/etoile-formation-conge/
curl -kfsS -o /dev/null -w 'nurse  %{http_code}\n' https://theses.lab.invalid/
```

If all three time out, it is the firewall or the adapter, not nginx — the
`Host:` loop above already proved nginx answers locally. If one 502s, that app
is down and the others are fine.

If those answer from the laptop and `ufw status` still shows default deny
inbound, the arrangement is right.

---

## 9. Seed the data — and why these numbers

```bash
cd ~/breakfix-lab
bash lib/seed.sh all
```

Verify it actually landed, per app — the seeder prints counts, but check the
apps agree:

```bash
curl -fsS http://127.0.0.1:8080/api/placements/count/; echo     # ~60000
curl -fsS http://127.0.0.1:8000/api/theses/ | head -c 200; echo  # not an empty list
cd /opt/stages && docker compose exec -T db psql -U stages_owner -d stages \
  -c "SELECT 'trainees', count(*) FROM trainees
      UNION ALL SELECT 'placements', count(*) FROM placements
      UNION ALL SELECT 'audit_log', count(*) FROM audit_log"
```

If `seed.sh` stops on `leaves` or `nurse` saying it cannot find a model, it
prints every model it did find: put the right name in `LEAVES_SEED_MODEL` or
`NURSE_SEED_MODEL` in `lab.conf` and run it again. It seeds `stages` first, so a
failure there does not cost you the volume that matters.

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
systemctl is-active nginx leaves nurse-api postgresql
docker compose -p stages ps        # stages is the only containerised app
```

All three answer, `placements` holds the seeded volume, every container reports
`(healthy)`. Now:

```bash
cd ~/breakfix-lab && lab list      # the catalogue, nothing passed yet
```

Shut down and snapshot as **`deployed`**.

`deployed` means: everything in `clean`, plus all three applications running and
seeded — `stages` in containers, `leaves` and `nurse` under systemd — the host
nginx in front of them, TLS in place, and `lab.conf` filled in with your real
`LAB_LAN_IP`. This is the snapshot almost every challenge expects,
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
| `s6-01` … `s6-04`, `s6-06`, `s6-07` | `deployed` | s6-01 needs the second disk from section 2, and the apps must keep serving throughout. s6-02 and s6-07 containerise `leaves` and `nurse`; change that app's mode in `lab.conf` when you pass one |
| `s6-05` | `clean` | Ansible rebuilds from near-bare. The final proof — "a fresh VM reaches a working state from the playbook alone" — needs a **new VM**, not a snapshot |
| `s7-01` … `s7-06` | `deployed` | "Off-VM" is always simulated locally: a second container, a separate mount, or a second VM. Never a real cloud account |
| **`s7-07`** | `deployed` | **Snapshot required.** `RISK=irreversible`: the fake uploads are scrambled and local backups removed |
| `s8-01`, `s8-02`, `s8-03` | neither | These start from a **bare Ubuntu 24.04 image**. s8-02 deletes the VM on purpose; rebuilding from Git and backups alone is the exercise. Keep `deployed` so you have something to compare against |
| `s9-01` … `s9-07` | `deployed` | Including the empty round in s9-06. `lab chaos` draws only from reversible level 2–4 challenges, so it will never fire s4-06, s5-07 or s7-07 |

Two snapshots, then. Most of the time you want `deployed`. Reach for `clean`
when a challenge has gone further wrong than `reset.sh` can follow, and when a
rebuild mission wants to start before the apps existed.
