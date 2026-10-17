# Break-Fix Lab — Build Instructions

A training lab for three web applications I wrote and deploy myself. It hands me
missions and incidents, checks my fixes, and writes reports I get graded on.

Build it section by section. Stop at each checkpoint in §9.

---

## 1. The three apps

**App A — `stages` (private repo `isepsi-stages`).** Hospital-internship management
for a nursing school.

- FastAPI (Python 3.12) + SQLAlchemy 2 + Alembic + PostgreSQL 16; React + Vite +
  TypeScript frontend; WeasyPrint for PDF printing; openpyxl for Excel import/export.
- Docker Compose, project name `isepsi`, three services: `db`, `api`, `web`. `web`
  is an nginx container serving the built frontend and proxying to `api`.
- Two networks, `front` and `back`, where `back` is `internal: true`, so the
  database is unreachable from outside. Volumes `db_data` and `uploads`.
  Healthchecks on all three; `web` waits for `api` to be healthy.
- Host nginx terminates TLS (certbot) and proxies to the `web` container on
  `127.0.0.1:8080`.
- Two database roles: an owner used for migrations, and a restricted `isepsi_app`
  role the application connects with, which has only `SELECT, INSERT` on
  `audit_log` (append-only).
- Operations tooling in `deploy/`: systemd units and timers `isepsi-backup`,
  `isepsi-watch`, `isepsi-preflight`, `isepsi-failure@`; backup scripts using `age`
  encryption plus `rclone` to Google Drive; a retention module; `row-counts.sql` as
  the restore fingerprint; a Telegram notifier; a fail2ban jail for SSH only.
- Config checks in `scripts/`: `check-deployment-config.sh`, `check-headers.sh`,
  `check-dependencies.sh`, `generate-secrets.sh`. The API **refuses to start** in
  production if `JWT_SECRET` is still the default, if `FORWARDED_ALLOW_IPS` is
  empty, or if `DEBUG=true`.

**App B — `leaves` (public repo `leaves_management_system`, use `v3.0`).** Staff
leave requests with HR then CEO approval.

- Django 5.2.7 + PostgreSQL, served by Gunicorn, static files by WhiteNoise,
  `dj-database-url` for `DATABASE_URL`, `python-decouple` for settings.
- `SECRET_KEY = config('SECRET_KEY')` has **no default**, so a missing environment
  variable crashes the app at startup. `DEBUG` defaults to `False`.
  `ALLOWED_HOSTS` comes from the environment.
- Everything is mounted under the URL prefix `/etoile-formation-conge/`, including
  `admin/` and `login/`. `LOGIN_URL` and `LOGIN_REDIRECT_URL` point inside it.
- `build.sh` runs `pip install`, `collectstatic --no-input`, `migrate`, then seeds
  an `rh_admin` user.

**App C — `nurse` (public repo `nurse`).** A searchable catalogue of nursing theses
with a staff area.

- Django 5.0.1 + Django REST Framework + PostgreSQL, Gunicorn, WhiteNoise with
  `CompressedManifestStaticFilesStorage`, `django-cors-headers`, pandas/openpyxl
  for Excel import.
- API under `/api/`, with `/api/health/`, `/api/auth/login/`, `/api/auth/me/`,
  `/api/upload/excel/`.
- **Two real weaknesses to use as material:** `SECRET_KEY` falls back to a
  hard-coded insecure default, and `DEBUG` defaults to `True` when unset.
- `CORS_ALLOWED_ORIGINS` and `CSRF_TRUSTED_ORIGINS` come from the environment;
  `CSRF_COOKIE_SECURE = True` and `CSRF_COOKIE_SAMESITE = 'None'`.
- Frontend is React + Vite + Tailwind, built to `dist/`. `VITE_API_URL` is read at
  **build time**, so a wrong value is baked into the bundle and only shows up in
  the browser.

**In my lab** all three run on one Ubuntu 24.04 VM behind one host nginx, with fake
data only. **Only `stages` is containerised.** Neither public repository ships a
Dockerfile or a compose file — `leaves` has `render.yaml` and `README_VPS.md`,
`nurse` has `render.yaml`, `build.sh` and `deployment/setup_vps.sh` with a
`settings_production.py` — and both describe gunicorn deployments, so both run as
gunicorn under systemd. Containerising them is s6-02 and s6-07.

**Each repository is the authority on its own deployment.** `SETUP.md` §6 and §7
are a summary of documentation written by someone else; where the two disagree,
the repository wins and the disagreement gets written down rather than guessed
at.

**Development happens on Parrot; the lab VM is Ubuntu 24.04.** Where the two
differ — package names, `ssh.socket` socket activation, the default `ufw` state —
the scripts target **Ubuntu 24.04**, and `SETUP.md` says so. Anything that needs
the lab marker to be present is verified in a disposable `ubuntu:24.04`
container, never on the development machine.

**What must not be tested on the development machine at all.** A container's
writable layer is the host's disk, so a container is *not* isolation for disk
space. A challenge is written, linted, reasoned about, marked `PROVEN=unproven`
and listed for the VM — never container-tested — when its break:

- writes more than a few hundred megabytes, or
- creates, formats or unmounts a filesystem outside a bounded loop image, or
- touches `/etc/fstab`, the boot path, or anything that decides whether the
  machine comes up.

This is not caution for its own sake: a loopback mount failed inside a container,
the break fell back to the filesystem underneath, and roughly 310 GB landed on
the development machine's root volume before the container was stopped. The
guards added since would now refuse — and the policy stands anyway, because the
next hole will be somewhere else. s5-07, which boots the VM to emergency mode,
cannot be container-tested in any form.

---

## 2. Safety rules (non-negotiable)

These apply to every file you generate. A break script that can run outside the lab
is a bug, not a feature.

1. **The lab marker gate.** Every script that changes the system must source
   `lib/guard.sh` and call `lab_guard` as its first action. `lab_guard` exits
   non-zero unless `/etc/breakfix-lab` exists and contains exactly `breakfix-lab`.
   No flag, environment variable or argument may bypass it.
2. **A second gate on identity.** `lab_guard` also refuses to run if the hostname
   contains `prod`, `vps` or `isepsi`, or if any filesystem is mounted from a path
   under `/opt/isepsi`. Refusing wrongly is cheap; running wrongly is not.
3. **Fake data only.** Nothing may contain, generate or require real student, staff
   or patient data. Seed data is invented names. If a challenge needs a database,
   it seeds its own.
4. **No secrets, ever.** No `.env`, keys, tokens, real domains, real IPs or real
   hostnames. `.gitignore` must exclude `lab.conf`, `reports/`, `*.env`, `*.key`,
   `*.dump`, `*.tar.age`.
5. **Every break is reversible.** Each incident ships a `reset.sh` that undoes it.
   Where that is impossible (a dropped database), the brief says "snapshot
   required" and `break.sh` refuses to run unless the user confirms at a prompt.
6. **Breaks are honest, not sneaky.** A break may hide its cause, but must never
   corrupt data outside the challenge's scope, consume unbounded disk, leave an
   unkillable process, or change anything about SSH access that could lock the user
   out of the VM. SSH-lockout practice belongs in its own challenge, which says so
   loudly and requires console access.
7. **`check.sh` proves the fix, not the symptom.** It verifies the end state the
   user cares about — the page answers 200, the service survives a restart, the row
   counts match — not merely that a file was edited. Exit 0 on pass, 1 on fail, one
   line printed per assertion.
8. **No network calls.** Nothing downloads anything at run time. The lab works on a
   VM with no internet beyond the package mirrors.
9. **Bash discipline.** Every script starts with `#!/usr/bin/env bash`,
   `set -euo pipefail` **and `shopt -s inherit_errexit`**, quotes all variables,
   and passes `shellcheck` with no warnings. Add a `make lint` target that runs
   `shellcheck` over everything.

   `inherit_errexit` is not optional decoration. Without it, `errexit` does not
   reach inside `$( )`, so a function that fails half way through a command
   substitution returns its partial output **with status 0** and the caller
   carries on. This was found the hard way: `lab_fs_make` failed to mount its
   loopback filesystem, returned the unmounted path anyway, and the break script
   went on to fill whatever filesystem that path happened to sit on — which in a
   container was the host's disk. A "bounded" filesystem that silently falls back
   to an unbounded one is worse than no bound at all.

   So, in addition: **a function that returns a path the caller will write to
   must verify that path**, and the caller must verify it again. Belt and braces,
   because `errexit` is not a safety mechanism — it is a convenience, and it has
   at least one hole in it per shell.

   **`make lint` fails if any script under `bin/`, `lib/` or `challenges/` is
   missing the shebang, `set -euo pipefail` or `shopt -s inherit_errexit`**, and
   `make selftest` reports the count. Having remembered to add three lines is not
   a guarantee; a build that refuses without them is. A new challenge that forgets
   either one fails the build rather than slipping through — the same reasoning as
   the positive control on an absence assertion: a guarantee nobody verifies is
   not a guarantee.
10. **Idempotent.** Running `break.sh` twice does not deepen the damage; running
    `reset.sh` twice is harmless.

---

## 3. Repo structure

Create exactly this tree. Keep every script small enough to read in one screen.

```
breakfix-lab/
  README.md               what this is, how to set up the VM, the rules of the game
  SETUP.md                building the lab VM and deploying the 3 apps with fake data
  FIRST-RUN.md            SETUP.md in session order: gates, snapshots, what to capture
  CLAUDE.md               the standing rules (see §9)
  Makefile                lint (shellcheck), test (run every check against a clean VM)
  lab.conf.example        URLs, service names and paths; copied to lab.conf and edited
  .gitignore              lab.conf, reports/, *.env, *.key, *.dump, *.tar.age
  bin/lab                 the CLI (single bash script)
  lib/guard.sh            lab_guard, the safety gate; state helpers
  lib/svc.sh              service control that works for compose and systemd
  lib/assert.sh           assertion helpers for check scripts, with pass/fail output
  lib/seed.sh             seeds fake data into each app's database
  lib/load.sh             load generator: requests/sec, p50, p95, error rate (§6 stage 9)
  lib/fs.sh               bounded loopback filesystems: make, destroy, measure (see below)
  report-template.md      the report skeleton `lab report` copies
  stages-lab/             the App A stand-in: FastAPI + Postgres + nginx, built in §3 of SETUP.md
  challenges/<id>/        one folder per challenge (format in §5)
  reports/                filled-in reports, gitignored
  solutions/<id>.md       the model answer, for after you pass
```

`lab.conf.example` holds everything environment-specific, so no challenge
hard-codes a path:

```bash
RUN_MODE="compose"            # or "systemd"
STAGES_DIR="/opt/stages";  STAGES_URL="http://localhost:8080/"
LEAVES_DIR="/opt/leaves";  LEAVES_URL="http://localhost:8081/etoile-formation-conge/"
NURSE_DIR="/opt/nurse";    NURSE_API="http://localhost:8000/api/health/"
NURSE_WEB="http://localhost:3000/"
DB_SERVICE="db"
BACKUP_DIR="/var/backups/lab"
```

**Resource-exhaustion challenges run on bounded loopback filesystems, not on the
host's volumes.** `lib/fs.sh` creates a fixed-size image, formats it, mounts it
under `LAB_SCRATCH_MNT`, and destroys it again, refusing to touch any mount that
is not one of its own loop devices. Three reasons, all learned the hard way:

- **A break must not be able to eat a host.** Filling the root volume of a
  machine the lab was pointed at by mistake is not recoverable by `reset.sh`.
- **Cleanup cost is a design constraint.** The original s5-02 — a million tiny
  files — takes minutes to create and far longer to remove, which makes
  `reset.sh` the slowest thing in the repo and turns a twenty-minute drill into
  an hour. A 64 MB filesystem formatted with 2048 inodes exhausts in seconds and
  resets by reformatting, which is O(1) rather than a traversal. The lesson is
  identical; the cost is not.
- **The diagnosis changes with the filesystem**, so every such brief names the
  mount point it is talking about. "The disk is full" on a lab with several
  loopback mounts is a different investigation from the root volume filling, and
  pretending otherwise teaches the wrong reflex.

`SETUP.md` is the part that teaches before it tests. Write it as a numbered
procedure that gets all three apps running on a fresh Ubuntu 24.04 VM with invented
data: install Docker and nginx, clone the two public repos, generate throwaway
secrets, run migrations, seed fake records, put all three behind one host nginx on
separate ports or paths, then verify each one answers. End with a "take a snapshot
now and name it `clean`" step, and a table of which snapshot each challenge expects.

---

## 4. The lab CLI

`bin/lab` is one bash script. Progress lives in `~/.breakfix-progress/`, never in
the repo.

| Command | What it does |
| --- | --- |
| `lab list` | Table of every challenge: id, stage, type, title, and a tick when passed. Shows elapsed time for anything in progress. |
| `lab start <id>` | Prints the brief. For an incident, demands an explicit `yes` that a snapshot exists, then runs `break.sh` and starts a timer. For a mission, prints the goal and the standard it will be checked against. |
| `lab hint <id>` | Reveals the next unread line of `hints.md`, one per call, and records how many were used. |
| `lab check <id>` | Runs `check.sh`, prints one line per assertion, stops the timer on pass and records hints used. Fails loudly otherwise. |
| `lab report <id>` | Copies `report-template.md` to `reports/<id>.md`, pre-filled with the id, title, timer and hint count. |
| `lab solution <id>` | Prints `solutions/<id>.md`. Refuses unless the challenge is passed or `--give-up` is passed, which marks it unpassed. |
| `lab reset <id>` | Runs `reset.sh`. |
| `lab status` | What is currently broken, since when. |
| `lab next` | Suggests the lowest-numbered unpassed challenge whose prerequisites are met. |

Design notes:

- A challenge's `meta` file is shell-sourceable: `STAGE`, `TYPE` (`mission` or
  `incident`), `TITLE`, `LEVEL` (1–5), `APPS` (which of stages/leaves/nurse it
  touches, or `system`), `NEEDS` (prerequisite ids), `SNAPSHOT` (`clean` or
  `deployed`), `PROVEN` (below), and `RISK`, which is empty for everything that `reset.sh` can
  undo and `irreversible` for the few that it cannot. `RISK=irreversible` is
  what excludes a challenge from `lab chaos` and from `make test`, so it is not
  optional decoration: a challenge whose brief says "snapshot required" must
  carry it.
- **`PROVEN` records how a challenge has actually been verified**, because
  "shellcheck is clean" is not the same claim as "I watched this break and
  recover". One of four values: `mock-systemd` or `mock-compose` (exercised
  against a stand-in service manager, which proves the challenge's logic but not
  the real application), `real` (exercised against the real thing on the lab VM),
  or `unproven` (written and linted, never run). `make selftest` prints the
  counts, so "what should I re-verify first" has a one-command answer. Update the
  field by hand after a real run — it is a record, not an assertion, and nothing
  enforces it but honesty.
- **Only `start`, `check` and `reset` require `lab.conf`**, because only those
  three touch the running system. `list`, `status`, `next`, `hint`, `report`,
  `solution` and `--help` read nothing but this repo and the progress state, so
  they must work without it and must not refuse. `status` above all: it is the
  command to reach for when something is broken and I am disoriented, and
  refusing it because a config file is absent is the opposite of useful. When a
  command that does need `lab.conf` cannot find it, say exactly what to copy
  where. (This reverses an earlier version of this rule that allowed only `list`
  and `--help` to work without config. The earlier rule was wrong: it made the
  diagnostic commands depend on setup having been finished.)
- **`RUN_MODE` is a default, not a global.** The lab does not run all three apps
  the same way, and cannot: s6-02 is a mission to *containerise* `leaves`, which
  is only possible if `leaves` starts life as gunicorn under systemd, while s4-04
  needs an app with genuinely published container ports. So `lab.conf` carries
  `STAGES_MODE`, `LEAVES_MODE` and `NURSE_MODE`, each falling back to `RUN_MODE`
  when unset, and `lib/svc.sh` resolves the mode **per app** rather than once.
  As built, only `stages` is containerised: neither public repository ships a
  Dockerfile or a compose file, so `leaves` and `nurse` both run as gunicorn
  under systemd, which is what their own deployment documents assume. A challenge that touches two apps may therefore be talking to
  systemd and to compose in the same script, and must not assume otherwise.
  (This replaces the single global `RUN_MODE` of the original §3: s3-01's own
  break description — "corrupt the `ExecStart` path, *or* in compose mode set the
  API command to a module that does not exist" — already assumed per-app modes
  without saying so.)
- Keep output plain and short. Colour only for pass, fail and the challenge title.
- No `sudo` inside `lab` itself; individual scripts call `sudo` where they need it,
  so the user sees exactly what is escalated.

---

## 5. Challenge format

Every challenge folder holds the same seven files.

```
challenges/s3-01-service-wont-start/
  meta          STAGE=3 TYPE=incident TITLE="..." LEVEL=2 APPS=leaves NEEDS= SNAPSHOT=deployed RISK= PROVEN=mock-systemd
  brief.md      the ticket, written as a user or a colleague would report it
  break.sh      guarded; causes the fault; records state; prints nothing useful
  check.sh      guarded; asserts the end state; one line per assertion; 0 or 1
  hints.md      one hint per line, ordered from gentle nudge to near-answer
  reset.sh      guarded; undoes break.sh
  notes.md      for the author: what the fault really is, why it is realistic, and the trap
```

**`brief.md` is a ticket, not a lesson.** It says what someone noticed and when, in
the voice of whoever would notice it, and nothing about the cause.
Good: *"HR says the leave app shows a 502 since about 14:00. It worked this
morning. The CEO needs to approve three requests before Friday."*
Bad: *"The gunicorn socket permissions were changed, fix them."*

**Name the trap, and make `check.sh` refuse it.** Wherever a plausible wrong fix
exists — one that makes the symptom go away while leaving the cause in place —
`notes.md` names it explicitly under the heading **The trap**, and `check.sh`
must catch it. s3-01 is the model: hand-starting gunicorn restores the page, so
the check restarts the service through the service manager, and a hand-started
process cannot pass. The point is not to be clever; it is that the shortcut which
treats the symptom is the habit that makes a server work until the next reboot.

Not every fault has one, and a strained invention is worse than none: if the only
way to make the symptom go away is to fix the cause, say so in `notes.md` and
move on. But where the shortcut is obvious — `chmod 777`, `DEBUG=True`, "any
database rather than the right database", a `NOPASSWD` entry broader than it
needs to be — the check refuses it, and the brief never hints that it will.

**A check must terminate, and the library enforces it.** Every assertion in
`lib/assert.sh` runs under a hard deadline — `ASSERT_TIMEOUT`, 30 seconds by
default — and a deadline reached is reported as `FAIL … assertion timed out`
rather than left to hang. A hang is worse than a failure: a failure is
information, a hang is a drill abandoned twenty minutes in.

This is mechanical rather than advisory on purpose. An `lsof +L1` scan in s5-03
hung for twenty minutes during testing *after* a rule saying checks must
terminate had already been written down. The rule did not stop it; a deadline
does. Prefer a primitive that cannot block anyway — s5-03 now reads `/proc/*/fd`
directly rather than calling `lsof` — but do not rely on having remembered to.

Detectors and planters passed to `assert_absent` run in a subshell, so they
inherit the caller's functions and variables but cannot hand variables back:
anything that must persist goes to a file.

**Every absence assertion carries a positive control.** Where `check.sh` claims
something is *gone* — no process holds the deleted file, the memory hog is
absent, no spinning loops remain, the OOM kills have stopped — it must also prove
that its own detection method works, by planting a known instance, requiring the
detector to find it, removing it, and only then asserting absence. A detector
that cannot see a planted instance makes the assertion fail with **"cannot verify
absence"** rather than passing silently.

This is the most dangerous bug class in the lab. A check that greps for a pattern
that can never match passes every time and proves nothing, and it is invisible
precisely when it matters: the fault is fixed, the check is green, and the green
means nothing. `make lint` earns its credibility the same way — by having found a
real SC2318 — and an absence assertion has to earn its own.

`lib/assert.sh` provides `assert_absent <description> <detect_fn> <plant_fn>
<clean_fn>` for this. A *measurement* is not an absence claim: "disk usage is
under 80%" needs no control, because the number is read directly. "The file that
filled it is gone" does.

**And a positive claim is its own evidence.** "The job succeeds under `env -i`",
"the process listening on this port is the service" — these are stronger than the
absence claims they imply, and they need no control. Do not dress one up as an
absence assertion: **the control must be planted in the real subject's own
domain, or the assertion proves only that the detector works**. Two checks in
Stage 5 were written that way and had to be rewritten — s5-06's pointed its
detector at a spare port and passed while a squatter held the real one, which is
a vacuous PASS wearing a control as a disguise. If the control cannot be planted
where the real claim lives, the claim probably wants to be positive.

**Vary the reporter.** Briefs written in a batch drift into one voice, and a
catalogue where every ticket sounds the same trains you to read tickets you will
never receive. Mix deliberately:

- a user who describes the symptom **wrongly** — "the site has been redesigned",
  when the stylesheet failed to load;
- a colleague who **already tried something** and made it worse;
- a **monitoring alert**: a timestamp, a threshold, no interpretation;
- someone **vague** — "it's been weird since this morning";
- and the most useful kind: one where the **reported symptom and the real fault
  are in different components**, so the first instinct sends you to the wrong
  layer entirely.

**`break.sh` hides the cause without being unfair.** The evidence must be findable
with ordinary tools — `systemctl status`, `journalctl`, `docker compose logs`, `ss`,
`df`, `ls -l`, `dig`, `curl -v`. Never require guessing.

**`hints.md` is a ladder of four to six lines:** first which layer to look at, then
which tool, then what the tool will show, then the cause, then the fix. Each line
must be useful on its own.

**`solutions/<id>.md` is the model answer** in the same shape as the report:
symptom, investigation commands with what each one reveals, root cause, fix,
prevention.

**Level meanings:** 1 one obvious cause; 2 a configuration mistake; 3 a cause hidden
from the obvious symptom; 4 two faults where fixing one reveals the other; 5 a
security incident with traces to find.

---

## 6. Challenge catalogue

Generate all seven files for each challenge. Where I give "break" and "check",
those are the requirements, not the code — write the scripts yourself and make them
work in both `compose` and `systemd` mode.

### Stage 2 — Bash and logs (missions)

- **s2-01 Read the access log** (L1, nurse) — ship a seeded 50k-line nginx access
  log. Six questions: top 10 IPs, top 10 URLs, requests per status code, 5xx per
  hour, the one IP responsible for most 404s, bytes served. *Check:* compares the
  user's `answers.txt` against values the script computes itself.
- **s2-02 `sysinfo.sh`** (L1) — hostname, uptime, load, memory used, disk used %,
  top 5 processes by memory. *Check:* runs it, asserts each field is present and
  numeric, and that it passes shellcheck.
- **s2-03 `appcheck.sh`** (L2, all three) — curls all three apps, warns over 80%
  disk or low memory, timestamps every line, exits non-zero on any failure.
  *Check:* stops one app, asserts the script exits non-zero and names that app;
  restarts it and asserts exit 0.
- **s2-04 Rotate the app logs** (L2, leaves) — write a logrotate rule: daily, keep
  7, compressed. *Check:* forces a rotation, asserts the rotated file is
  compressed, the count is right, and the app is still writing to the new file.

### Stage 3 — Services, logs, users, permissions (incidents)

- **s3-01 The leave app returns 502** (L2, leaves) — *break:* corrupt the
  `ExecStart` path in the Gunicorn unit, or in compose mode set the API command to
  a module that does not exist; reload so the running process keeps serving until
  restarted. *Check:* the app answers 200 **and** still answers after a full
  restart.
- **s3-02 Theses API is down, site shows an empty list** (L2, nurse) — *break:*
  point `DATABASE_URL` at the wrong port. *Check:* `/api/health/` returns 200 and
  the list endpoint returns rows.
- **s3-03 The leave app will not start at all** (L2, leaves) — *break:* remove
  `SECRET_KEY` from the environment file. This app has no default, so it dies at
  import. *Check:* app answers 200, and `SECRET_KEY` is present, at least 40
  characters, and not any value shipped in the repo.
- **s3-04 Pages load but look broken** (L2, leaves) — *break:* empty `staticfiles/`
  and the WhiteNoise manifest. *Check:* a known CSS asset returns 200 with the
  right content type.
- **s3-05 Nobody can upload the school logo** (L2, stages) — *break:* change owner
  and mode on the uploads volume path so the app user cannot write. *Check:* the
  upload endpoint writes a file and reads it back; `namei -l` on the path shows a
  traversable chain.
- **s3-06 It works until the server reboots** (L2, nurse) — *break:* disable the
  unit, or set `restart: "no"` in compose. *Check:* reboots the VM (or restarts the
  Docker daemon), waits, then asserts the app answers unaided.
- **s3-07 A developer has too much sudo** (L1, system) — *break:* grant a `dev1`
  user blanket `ALL=(ALL) NOPASSWD: ALL`. *Check:* `dev1` can restart nginx and
  nothing else; asserts a `sudo -l` listing with exactly one permitted command.

### Stage 4 — Networking and hardening

- **s4-01 Reachable from the server, not from my laptop** (L3) — *break:* a
  firewall rule that drops the app port while leaving loopback working. *Check:* a
  request to the VM's own LAN address succeeds, and `ufw status` shows default deny
  inbound with only the expected ports.
- **s4-02 Nothing resolves** (L2) — *break:* a bogus nameserver in the resolver
  configuration. *Check:* `dig` resolves a name, and the apps can reach their
  database by name.
- **s4-03 Browsers warn about the certificate** (L3) — *break:* swap in an expired
  self-signed certificate. *Check:* TLS handshake succeeds, the certificate has
  more than 14 days left, and HTTPS returns 200.
- **s4-04 Docker goes around the firewall** (L3, stages) — *mission:* publish a
  container port, deny it in ufw, and prove from the VM's LAN address that it is
  still reachable. It targets `stages` because that is the only containerised app
  in the lab as built — see §1 — and therefore the only one with real published
  ports to argue about. Then fix it two ways: bind to `127.0.0.1` behind nginx, and
  filter in the `DOCKER-USER` chain. *Check:* the denied port is genuinely
  unreachable while the app still works through nginx.
- **s4-05 Raise the hardening score** (L2, mission) — run `lynis audit system`,
  record the score, fix the top five findings, re-run. *Check:* the score improved,
  SSH is key-only with root login disabled, and the open-port list matches the
  expected set exactly.
- **s4-06 Locked out of SSH** (L4, **snapshot and console access required**,
  `RISK=irreversible`) — *break:* a firewall rule and an `sshd` change that
  together refuse new sessions while the session already open survives. Include
  the Ubuntu 24.04 socket-activation trap, where `Port` in `sshd_config` has no
  effect because `ssh.socket` owns the listener. The brief must state plainly
  that SSH will be lost and that recovery is through the hypervisor console, and
  `break.sh` must require typing `yes-i-have-console`. *Check:* a fresh SSH
  session succeeds on the intended port, `ufw` allows only the expected ports,
  and the socket override and `sshd_config` agree on that port. This is the one
  challenge exempt from the SSH clause of §2.6, which is why it says so loudly.
- **s4-07 Fix the weaknesses in nurse** (L2, mission, nurse) — make `SECRET_KEY`
  have no fallback, so a missing variable is a startup failure rather than a
  silent insecure default, and make `DEBUG` default to `False`. *Check:* with the
  variable unset the app refuses to start; with it set the app answers 200 and
  `DEBUG` is false. This is a real patch to a repo on a public GitHub account, so
  the diff stays small and the reasoning is written down.

### Stage 5 — Troubleshooting drills (incidents)

- **s5-01 Disk is full** (L2) — *break:* `fallocate` a large file in a non-obvious
  place. *Check:* under 80% used and all three apps answer.
- **s5-02 Disk has space but writes fail** (L3) — *break:* exhaust inodes with a
  million tiny files. *Check:* `df -i` under 80% and writes succeed.
- **s5-03 Disk full, and nothing big to delete** (L3) — *break:* a process holds a
  deleted multi-gigabyte log open. *Check:* space actually returned to the
  filesystem, with the holding process still running.
- **s5-04 The API keeps dying at random** (L3, nurse) — *break:* a memory hog plus
  a low cgroup limit, so the OOM killer picks the API. *Check:* the hog is gone, the
  app has survived ten minutes, and the OOM event is findable in `dmesg`.
- **s5-05 Everything is slow** (L2) — *break:* several spinning CPU loops under an
  innocuous name. *Check:* load average back under the core count and response time
  under a second.
- **s5-06 The service will not bind** (L2) — *break:* a decoy process squatting on
  the app's port. *Check:* the app owns the port and answers.
- **s5-07 The VM boots to emergency mode** (L4, **snapshot required**) — *break:* a
  bad UUID in `/etc/fstab`. *Check:* the VM boots unaided to a working state with
  all mounts present.
- **s5-08 Two things at once** (L4) — *break:* an invalid nginx `server` block
  **and** a stopped database. Fixing nginx reveals the 502. *Check:* both fixed and
  all three apps answer.
- **s5-09 The nightly job silently stopped** (L3) — *break:* a cron entry that
  depends on a `PATH` only an interactive shell has. *Check:* the job's output file
  is fresh, and the cron entry works under `env -i`.

### Stage 6 — Storage, containers, monitoring, automation (missions)

- **s6-01 Give Docker its own volume** (L3) — add a disk, build an LVM volume
  group, move `/var/lib/docker` onto it, mount by UUID, then extend it live while
  the apps keep serving. *Check:* mounted by UUID, survives reboot, apps up
  throughout, and the volume grew.
- **s6-02 Containerise the leave app** (L3, leaves) — a `Dockerfile` and
  `compose.yaml` with PostgreSQL, a named volume, an env file and a healthcheck.
  *Check:* destroy the containers, bring them back, and the data is still there.
- **s6-03 Monitoring that tells you first** (L3) — Prometheus with node_exporter
  and Grafana, or Netdata. Alerts for disk over 80%, a service down, and a
  certificate expiring within 14 days. *Check:* triggers each condition for real
  and asserts each alert fired.
- **s6-04 Your own watchdog** (L4) — build what the `stages` app has: seven checks
  on a timer, one notification channel, an alert only when the state **changes**,
  and a recovery message. No personal data in any message. *Check:* breaks one
  thing, asserts exactly one alert; leaves it broken a cycle, asserts silence;
  fixes it, asserts a recovery message.
- **s6-05 Rebuild the VM with one command** (L4) — Ansible roles for users, SSH
  hardening, firewall, Docker, nginx, the three apps, backups and monitoring.
  *Check:* a second run reports `changed=0`, and a fresh VM reaches a working state
  from the playbook alone.
- **s6-07 Containerise the theses app** (L3, nurse) — a `Dockerfile` for the API,
  a build for the frontend, and a `compose.yaml` with PostgreSQL, a named volume,
  an env file and healthchecks. *Check:* destroy the containers, bring them back,
  and the data is still there; the API answers on the same port it did under
  systemd; and `NURSE_MODE` flipped to `compose` leaves every challenge that
  touches nurse still passing.

  **Why this exists.** The original plan had setup containerise `nurse`, which
  assumed a Dockerfile the repository does not have: `nurse` ships `render.yaml`,
  `build.sh` and `deployment/setup_vps.sh` with a `settings_production.py`, all
  of which describe a gunicorn deployment. Writing an API Dockerfile, a frontend
  build and a compose file untested, in the middle of a first VM run, is a bad
  trade — and containerising an application is worth doing as a graded exercise
  with a check on it rather than invisibly during setup. The same reasoning
  already applied to `leaves` in s6-02; this extends it to the second repo.
- **s6-06 Deploy by tag, and roll back** (L3) — put the lab apps on git tags,
  deploy by naming a tag, then roll back to the previous tag. *Check:* the running
  version matches the tag, rollback restores the old behaviour, and no step used
  `git pull`.

### Stage 7 — Backups and security

- **s7-01 Backups worth having** (L3, mission) — restic or Borg: encrypted,
  scheduled by timer, 3-2-1 with one copy off the VM, sensible retention, and a
  success ping to a dead-man's-switch. *Check:* an archive exists off the VM, it is
  encrypted, retention is honoured, and killing the timer produces a missed-backup
  alert.
- **s7-02 Restore drills** (L3, mission) — restore one file, then a whole database,
  then everything onto a brand-new VM. Time each. *Check:* restored row counts
  match a fingerprint taken at backup time, and the times are recorded.
- **s7-03 The backups are gone** (L4, incident) — *break:* delete every local
  archive and corrupt the newest remote one. *Check:* the apps are restored from an
  older good archive, row counts match that archive's fingerprint, and the report
  states the data loss window actually achieved against the stated target.
- **s7-04 Backups an attacker cannot delete** (L4, mission) — make the off-VM copy
  append-only, then prove it: from the VM, try to delete an old archive and fail.
  *Check:* the delete attempt is refused and the archive is still there.
- **s7-05 Backups stopped three weeks ago** (L3, incident) — *break:* disable the
  timer and backdate the success marker. *Check:* an alert fired, backups are
  running again, and the gap is explained in the report.
- **s7-06 Someone was in here** (L5, incident) — *break:* plant four traces: a
  hidden account with a shell, an unknown key in `authorized_keys`, a cron job that
  re-adds the key, and a process listening on a high port under a plausible name.
  *Check:* all four gone, the cron job cannot restore itself, and the report lists
  every one of the four plus how it was found.
- **s7-07 Files are encrypted and the server is asking for money** (L5, incident,
  **snapshot required**) — *break:* rename and scramble the fake uploads and drop a
  ransom note; also remove local backups. *Check:* uploads restored from the off-VM
  copy, nothing of the attacker's left running, and an incident report written.

### Stage 8 — The big ones

- **s8-01 Build the server from nothing** (L4, mission, timed) — from a bare Ubuntu
  24.04 image: user and SSH keys, hardened SSH, firewall, Docker, host nginx with
  TLS, all three apps with fake data, backups running, monitoring alerting. Record
  the time. *Check:* a full acceptance suite — every app answers over HTTPS, the
  port list is exactly as expected, one backup has run and been restored, and one
  alert has fired and recovered.
- **s8-02 Disaster recovery day** (L5) — delete the VM. Rebuild from your Git repo
  and your backups alone, inside the recovery time you wrote down. *Check:* same
  suite as s8-01, plus restored data matching the last archive's fingerprint, plus
  the elapsed time against your target.
- **s8-03 The blind rebuild** (L5) — s8-01 again, but you may read only your own
  runbooks, with no internet and no AI. Every gap you hit is a gap in your
  documentation; fix the documentation afterwards. *Check:* same suite, plus a diff
  showing what you had to add to your runbooks.

### Stage 9 — Chaos, intermittent faults and load

This stage exists because a known fault fired on demand is a kinder world than
production. Everything here attacks a different assumption: that you know
something is broken, that it is broken all the time, and that there is exactly one
thing wrong.

**`lab chaos`** — a new CLI command, specified here rather than in §4 because it
depends on the catalogue existing.

- Picks from a pool of eligible incidents: any reversible challenge at level 2–4.
  The pool **excludes** anything marked snapshot-required or irreversible
  (`s5-07`, `s7-07`, `s4-06`).
- Fires one with probability 0.65, two at once with probability 0.20, and
  **nothing at all** with probability 0.15.
- Prints only the time and a round id. Never says what it did, or how many.
- Records the truth in a file the user cannot read casually — base64 is enough,
  this is a discipline aid not a security boundary. `lab chaos --reveal` prints it
  and marks the round as revealed.
- `lab chaos --check` does **not** check a specific fault. It asserts overall
  health: all three apps answer, disk and inode usage sane, memory sane, every
  expected service enabled and running, the backup marker fresh, no unexpected
  listening ports, no unexpected users. A round where nothing fired is passed by
  **proving health**, not by finding a fault.
- A report is required for every round, including the empty ones. For an empty
  round the report states how you concluded the system was healthy and what you
  checked to be sure.

**The best version of this needs a person.** Have a friend run `lab chaos` and
describe the symptom to you in their own words, over chat, while you cannot see
their screen. That is the actual job, and no script reproduces it.

**`lib/load.sh`** — a small load generator the load challenges depend on. Parallel
`curl` is enough; use `hey` or `ab` if available from the mirrors. It must report
requests per second, p50 and p95 latency, and the error rate, because "it felt
slow" is not a measurement. Add it to the tree in §3.

**`lib/assert.sh` gains a reusable `health_check` function** that both
`lab chaos --check` and the Stage 8 acceptance suite call, so "healthy" has one
definition.

- **s9-01 One request in five** (L4, nurse) — *break:* a fault that only shows on a
  fraction of requests — one Gunicorn worker started with a broken environment, or
  one upstream in the nginx block pointing somewhere wrong while the others are
  fine. *Check:* 100 consecutive requests all return 200, and the worker or
  upstream count is intact.
- **s9-02 Slow, but only under load** (L4) — *break:* starve the pool — a low
  gunicorn worker count, or a low PostgreSQL `max_connections`, or both. Nothing
  is visibly wrong at one request at a time; the queue only forms under
  concurrency. *Check:* p95 latency under a stated threshold at a stated
  concurrency, measured with `lib/load.sh`.
- **s9-07 The query that got slow** (L3) — *break:* drop the index on
  `placements (ward, started_on)`, which the seeded 60,000-row table depends on.
  *Check:* measured with `EXPLAIN (ANALYZE)` and query time, not with a load
  generator: the plan uses an index scan rather than a sequential scan, and the
  filtered query runs at least four times faster than the unindexed plan on the
  same data.

  **Why these are two challenges and not one.** The original s9-02 offered the
  worker limit and the missing index as alternatives for the same fault. Measuring
  the stand-in proved they are not interchangeable. At 60,000 rows the index is
  worth 3.1 ms against 14.7 ms — a 4.7× ratio, which is a fine signal for
  `EXPLAIN ANALYZE` but about 11 ms of wall clock, and on a 2 vCPU VM where
  `lib/load.sh` is competing for the same two cores, 11 ms disappears into the
  noise of the load generator itself. Starving a worker pool, by contrast, has a
  large and unambiguous effect on p95 under concurrency, because requests queue
  rather than merely running slower. So the load-shaped fault keeps the
  load-shaped measurement, and the index keeps a measurement that suits it.
- **s9-03 It gets worse over hours** (L4) — *break:* a slow leak — a log growing
  fast, an unbounded table, a process leaking memory. At minute one there is no
  symptom. *Check:* the growth rate is flat over a measured window, and the report
  states the rate before and after.
- **s9-04 The flapping service** (L3) — *break:* a service that crashes and
  restarts every few minutes, so it is always up whenever you look at it. *Check:*
  process uptime exceeds a threshold and the restart counter has stopped
  incrementing.
- **s9-05 Someone else changed something** (L4) — *break:* a change with no obvious
  connection to the symptom — a timezone change that breaks a timer, a locale
  change that breaks date parsing, an MTU change that breaks large responses only.
  *Check:* the symptom is gone **and** the report correctly identifies the
  unrelated change as the cause.
- **s9-06 Nothing is wrong** (L3) — *break:* a genuine no-op. The brief reports a
  user insisting the site is slow. *Check:* asserts health, and asserts the report
  concludes "no fault found" with the evidence that justifies it. Passing this
  requires saying nothing is broken and being able to defend it, which is harder
  than it sounds and is a real skill.

---

## 7. Report template

Generate `report-template.md` exactly as below. `lab report` fills in the id,
title, time and hints used.

```markdown
# __ID__ — __TITLE__

Date:            Time to fix:            Hints used:

## Symptom
What a user would have noticed, in one or two sentences.

## Investigation
The commands I ran, in order, and what each one told me.
The dead ends count — write them down too.

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|

## Root cause
The one sentence that explains everything above.

## Fix
What I changed, and why this is the right fix rather than a workaround.

## Verification
How I proved it was fixed, beyond the absence of the error.

## Prevention
What would have caught this sooner: a monitoring check, a config test,
a permission, a habit. Be specific enough to actually implement.

## What I did not know before this
One or two lines. This is the part that makes the next one faster.
```

---

## 8. Build order

Build in this order and stop at each checkpoint. Do not generate all forty
challenges before the first one works end to end.

1. **The skeleton.** `README.md`, `.gitignore`, `Makefile`, `lab.conf.example`,
   `lib/guard.sh`, `lib/svc.sh`, `lib/assert.sh`, `report-template.md`. Then write
   **one** throwaway challenge whose break stops a service, and prove the whole
   loop works: `list`, `start`, `hint`, `check`, `report`, `reset`.
2. **`bin/lab` in full**, to the specification in §4, including `next` and
   `solution`.
3. **`SETUP.md`** and `lib/seed.sh`, so the VM and the three apps can be built from
   nothing with fake data.
4. **Stage 3 and Stage 5 challenges** — fifteen of them. These are where I will
   spend most of my time, so they get the most care.
5. **Stage 2, 4, 6, 7** challenges.
6. **Stage 8**, a long acceptance suite plus a brief. Then **Stage 9**: build
   `lab chaos`, `lib/load.sh` and `health_check` first, then its seven challenges.
7. **A final consistency pass over `solutions/`** — not the writing of them.

**Every challenge ships `solutions/<id>.md` as part of building it**, in the same
sitting as its seven files, immediately after its check has been seen to pass and
fail. This replaces an earlier version of step 7, which deferred all fifty
solutions to the end. The reason for the change: the model answer is a record of
an evidence chain — which command revealed what, which dead end was worth
recording — and that chain is in hand exactly once, while the challenge is being
verified. Deferring fifty of them means re-deriving fifty cold, from the scripts
rather than from having watched them run, which produces a worse answer and a
slower build. Step 7 is now only the pass that makes the fifty consistent with
each other.

---

## 9. Acceptance checks

Before telling me it is done, run these and show me the output:

- `make lint` — shellcheck clean across every script.
- A self-test that, for every challenge, sources `meta` and asserts all seven files
  exist, `TYPE` is valid, `NEEDS` references real ids, and `hints.md` has at least
  four lines.
- A guard test: with `/etc/breakfix-lab` absent, **every** `break.sh` exits 97 and
  changes nothing. Show the count of scripts tested.
- A secret scan over the whole repo for anything resembling a key, token, password,
  real domain or real IP, and show that it found nothing.

These three live as `Makefile` targets — `make selftest`, `make guard-test` and
`make scan-secrets` — rather than as scripts in their own directory, so the tree
in §3 stays as specified. `make lint` runs `shellcheck -x -P <repo root>` so that
sourced libraries are followed. `make test` (break, prove the check fails, reset,
prove it passes) refuses to run unless `/etc/breakfix-lab` exists **and**
`LAB_DISPOSABLE=1` is set, so it cannot be aimed at a VM that matters, and it
skips anything carrying `RISK=irreversible`.

Also add a `CLAUDE.md` at the repo root saying: this repo is a training lab; every
system-modifying script must call `lab_guard` first; no real data, no secrets, no
network calls at run time; briefs describe symptoms and never causes.
