# FIRST-RUN.md — the first VM session, in order

`SETUP.md` has never been executed. This file is the order to execute it in, where
to stop, what to prove before going on, and what to write down so the results are
worth handing back.

Budget **three to four hours** for a first run, most of it waiting on two
container builds. Do not start it in the last hour of the day: the last step
deliberately stops the VM from booting.

---

## 0. Before you touch the VM

- [ ] Hypervisor open, and you know where **snapshot** and **console** are. Not
      "I could find them" — open the console on a running VM once now, so you are
      not learning that interface while the machine is down.
- [ ] A bridged adapter, not NAT. ([SETUP.md §2](SETUP.md))
- [ ] A second blank 10 GB disk attached and **unformatted**. `lsblk` must show it
      with no partitions. Nothing in this session uses it; s6-01 will.
- [ ] Your laptop can edit its own `/etc/hosts` (you will need admin on the laptop).
- [ ] Outbound internet from the VM. Two steps download a Python wheel set and an
      npm tree; without them the run stops at §5.

**Record the whole session.** One command, and every failure you hit becomes
reportable without you having to remember it:

```bash
script -a ~/lab-first-run.log
# ...do everything inside this shell...
# exit    # when you are done, to close the log
```

---

## 1. Base system → `clean` snapshot

Work through **SETUP.md §3** in order. The gates that matter:

| After | Prove it before continuing |
| --- | --- |
| step 0 | `whoami` is the account you will use for everything. Decide once. |
| step 1 | `wc -l ~/.ssh/authorized_keys` — the paste needs **Ctrl-D**, it is not hung |
| step 2 | `sudo sshd -T \| grep -E '^(passwordauthentication\|permitrootlogin)'` reads `no`/`no`. A second SSH session works. |
| step 3 | `sudo ufw status verbose` — default deny incoming, 22/80/443 allowed |
| step 4 | **log out and back in**, then `id -nG \| grep docker`, `docker version`, `systemctl is-active docker nginx postgresql` |
| step 5 | `cat -A /etc/breakfix-lab` reads `breakfix-lab$` |
| step 6 | `make lint && make selftest` both succeed; `lab list` prints 17 rows |

> **Stop here if** `make lint` fails, `docker version` fails as your user, or
> `sshd -T` still says `yes`. All three invalidate everything after them.

**→ Shut down. Snapshot as `clean`.** This is cheap and you will want it.

---

## 2. LAB_LAN_IP and hosts

**SETUP.md §4.** Boot, run the `LAN_IP` block, add the same line to your
laptop's `/etc/hosts`, and prove the laptop can reach the VM:

```bash
# from the laptop
ping -c1 stages.lab.invalid && nc -vz stages.lab.invalid 22
```

> **Stop here if** the laptop cannot reach the VM. It is the adapter or the
> firewall, and every networking challenge depends on it. Nothing later in this
> session needs it, so you *may* carry on and come back — but write it down.

---

## 3. The three apps, one at a time

Do them in this order, and **verify each before starting the next**. If you
build all three and then test, you will not know which one broke what.

Only `stages` is containerised. `leaves` and `nurse` both run as gunicorn under
systemd, because that is what their own deployment documents describe and
neither repository ships a Dockerfile. Containerising them is s6-02 and s6-07,
as graded exercises.

### 3a. Read each repository's own deployment docs first — a gate, not a nicety

**Before starting §6 and before starting §7**, read the repository's own
documentation and reconcile it with mine. `SETUP.md` is my summary of
documentation written by someone else; **where they disagree, the repository
wins.**

```bash
# leaves, before SETUP.md §6
cd /opt/leaves
sed -n '1,120p' README_VPS.md
sed -n '1,80p'  README_POSTGRESQL.md
ls -1 render.yaml build.sh 2>&1

# nurse, before SETUP.md §7
cd /opt/nurse
sed -n '1,100p' deployment/QUICK_START.md
sed -n '1,150p' deployment/setup_vps.sh        # read it; do not run it blind
sed -n '1,100p' deployment/CONFIG_TEMPLATES.md
sed -n '1,120p' settings_production.py         # the authority on what it reads
ls -1 render.yaml build.sh deployment/ 2>&1
```

For each app, write down before you build it:

| Question | From the repo | From SETUP.md | Which did you follow |
| --- | --- | --- | --- |
| WSGI entry point | | `leave_management_project.wsgi` / `config.wsgi` | |
| Settings module | | `settings_production` for nurse | |
| Environment variable names | | `SECRET_KEY`, `DEBUG`, `DATABASE_URL`, `ALLOWED_HOSTS` | |
| Where config is expected to live | | `/etc/leaves/leaves.env`, `/etc/nurse/nurse.env` | |
| Bind address and port | | `127.0.0.1:8081`, `127.0.0.1:8000` | |
| Static files / frontend build | | `collectstatic`; `npm run build` to `frontend/dist` | |
| What `build.sh` does | | seeds `rh_admin` (leaves) | |

**Report every disagreement, even the ones you resolved.** A guess that happens
to work is worse than a disagreement you can see, because it survives silently
into every challenge built on top of it. If `setup_vps.sh` does most of §7
properly, use it and tell me — §7 should then be rewritten to defer to it rather
than duplicate it.

### 3b. Then build them

1. **`stages`** — SETUP.md §5. The long one, and the only containerised app.
   After `--wait` returns, all three services must read `(healthy)`. Then run the
   four topology proofs and the three refuse-to-start proofs in that section;
   they are the reason the stand-in exists, and the parts most likely to disagree
   with my assumptions.
2. **`leaves`** — SETUP.md §6, after 3a. Note the `sudo bash -c` wrapper around
   the management commands: the env file is root-only on purpose.
3. **`nurse`** — SETUP.md §7, after 3a. Two unit-of-work questions to settle from
   its own docs: whether `setup_vps.sh` replaces most of the section, and whether
   the frontend build needs a pinned Node version. The API is a unit
   (`nurse-api.service`); the frontend is static files served by the host nginx.

After each one, the matching line of this must answer:

```bash
curl -fsS http://127.0.0.1:8080/api/health/ ; echo    # stages  (compose)
curl -fsS -o /dev/null -w 'leaves %{http_code}\n' http://127.0.0.1:8081/etoile-formation-conge/
curl -fsS http://127.0.0.1:8000/api/health/ ; echo    # nurse api (systemd)
curl -fsS -o /dev/null -w 'nurse web %{http_code}\n' http://127.0.0.1:3000/
```

The last one needs the nginx block from §8, so it will fail until then. That is
expected, not a fault.

---

## 4. nginx, TLS, seed → `deployed` snapshot

**SETUP.md §8**, then **§9**, then **§10**.

- §8's `Host:` loop must give three non-`000` answers from the VM.
- §8's laptop block must give three `200`s over HTTPS.
- §9's verification must show ~60,000 placements.
- §10 is the full sweep: three apps, two compose stacks, three services.

> **Stop here if** seeding fails on `stages`. If it fails only on `leaves` or
> `nurse`, note the model names it printed, set them in `lab.conf`, and carry on —
> those two do not block anything in this session.

**→ Shut down. Snapshot as `deployed`.** Every challenge below expects it.

---

## 5. Validate three challenges, in this order

These three are the ones I could not verify: `s3-06` and `s5-04` were never run
against the real thing, and `s5-07` was never run at all. The others are already
exercised; these are the ones that will tell us something.

### 5a. `s3-06` — works until the server reboots *(reboot, no console needed)*

```bash
lab start s3-06-works-until-reboot          # type yes
lab check s3-06-works-until-reboot          # expect: not armed yet
lab check s3-06-works-until-reboot --arm
sudo reboot
# wait, log back in, and TOUCH NOTHING:
lab check s3-06-works-until-reboot
lab reset s3-06-works-until-reboot
```

Expected: the check **fails** before the fix with nurse unreachable, and after
you `systemctl enable nurse-api` again, it passes with
`it started with the machine (Ns after boot)`. The assertion I am least sure of
is that start-time-against-boot-time comparison — record the exact numbers it
prints, pass or fail.

### 5b. `s5-04` — the API keeps dying *(no reboot, takes ~5 minutes of waiting)*

```bash
lab start s5-04-api-keeps-dying             # type yes
systemctl show -p NRestarts -p MemoryMax --value nurse-api
systemctl status --no-pager -l nurse-api | tail -5
sudo dmesg -T | grep -iE 'oom|killed' | tail -5
lab check s5-04-api-keeps-dying             # 3 minutes of watching, then fails
# fix it (remove the drop-in, or raise it), then:
lab check s5-04-api-keeps-dying
lab reset s5-04-api-keeps-dying
```

The limit lives in `/etc/systemd/system/nurse-api.service.d/90-lab.conf`.

Two things to record, because the whole design rests on them: whether the OOM
line says **`Memory cgroup out of memory`** and names the api's cgroup, and
whether the victim is the api **every** time (the restart counter should climb
steadily rather than randomly). If the global OOM killer picks something else —
postgres, the frontend build — the determinism claim is wrong and I need to know.

Also record whether the planted OOM control works: the check prints
`(detector proved against a planted instance)` on success, or
`cannot verify absence` if the throwaway cgroup could not be created.

### 5c. `s5-07` — boots to emergency mode *(LAST. Console open. Snapshot fresh.)*

Do this one **last, with the hypervisor console already open in front of you**,
and not when you need the VM for anything else today.

```bash
# Take a fresh snapshot FIRST, even though you have `deployed`.
lab start s5-07-boots-to-emergency          # type yes, then the typed phrase
lab check s5-07-boots-to-emergency --arm
sudo reboot
# it will NOT come back. Go to the console.
# Recover there, then from a normal session:
lab check s5-07-boots-to-emergency
```

Record: whether it actually reached emergency mode (or booted anyway, which
would mean the fstab entry was not a hard dependency — a real flaw), what the
console showed, and whether `mount -a` was clean before you rebooted. If
recovery goes wrong, roll back the snapshot; that is what it is for and it costs
nothing.

---

## 6. What to send back

A short file beats a long conversation. For each of the three challenges:

```
s3-06 — PASS / FAIL / DID NOT GET THERE
  break:    what the symptom actually looked like
  check:    the assertion lines, verbatim, pass and fail
  fix:      what you changed
  surprises: anything the brief or hints got wrong about reality
```

Plus, for the setup itself:

- **Which SETUP.md step numbers you had to deviate from, and how.** This is the
  most valuable thing in the whole report.
- Any step where you had to look something up that the file should have told you.
- Any step with **no verification command** where you later found you had carried
  an error forward.
- Total elapsed time, and which step ate it.

Send `~/lab-first-run.log` if it is not too large; `gzip` it if it is.

---

## 6b. Before you report anything: run lab doctor

```bash
lab doctor
```

It checks the lab rather than the challenge: every `lab.conf` value pointing at
something real, every app answering where config says, every unit or container
present with its mode matching, the marker, the tools, loop devices, seed
volumes, writable state, and anything left broken. Failures print first and each
carries the next command.

Paste its output into your report. If it is clean, say so — "lab doctor clean"
tells me the fault is in a challenge and not in the ground it stands on, which
halves the search.

`SOLO.md` is the companion to this: what to do about each kind of failure when
there is nobody to ask.

---

## 7. When something fails, capture these four things

"It didn't work" costs us a round trip. These four make it one:

1. **The exact command**, copy-pasted, not retyped.
2. **The full error**, not the last line. Scroll up.
3. **The state around it** — the layer-appropriate block below.
4. **What you expected instead**, in one sentence.

```bash
# --- a systemd service (leaves, nginx, postgresql, docker)
systemctl status --no-pager -l <unit>
journalctl -u <unit> -n 60 --no-pager
systemctl show -p FragmentPath -p EnvironmentFiles -p MainPID -p NRestarts <unit>

# --- a compose stack (stages only, as built)
cd /opt/<app> && docker compose ps -a
docker compose logs --tail 80 <service>
docker compose config | head -40
docker inspect -f '{{.State.Status}} {{.State.Health.Status}} {{.RestartCount}}' "$(docker compose ps -q <service>)"

# --- nginx
sudo nginx -t
curl -sv -o /dev/null -H "Host: conge.lab.invalid" http://127.0.0.1/ 2>&1 | tail -20

# --- a database
sudo -u postgres psql -c '\l'                       # host postgres, for leaves
cd /opt/stages && docker compose exec -T db psql -U stages_owner -d stages -c '\dt'

# --- a lab script that misbehaved
bash -x challenges/<id>/break.sh 2>&1 | tail -40     # the -x is the point
cat ~/.breakfix-progress/state/<id>/vars
```

And always, regardless of layer:

```bash
{ date -Is; whoami; id -nG; uname -a; df -h /; free -m; } 
```

---

## 8. Where I expect trouble, ranked

I fixed what was clearly wrong. These are the places I could not fix from here,
so look hardest at them:

1. **The two public repos.** Every claim about `leaves`' and `nurse`' layout —
   WSGI paths, settings module, environment variable names, model names, migration
   heads, `build.sh`, `create_default_superuser` — comes from what you told me,
   not from reading them. §3a is the gate for this, and it is the single most
   valuable half-hour of the session.
2. **`deployment/setup_vps.sh` in `nurse`.** It probably does most of §7, and
   better, since it was written against the actual code. If so, §7 should defer
   to it instead of duplicating it. Read it; tell me what it covers.
3. **`build.sh` in `leaves`** and **`build.sh` in `nurse`.** I do not know what
   either does. Read before running.
4. **The nurse frontend build.** `VITE_API_URL` must be set in the environment of
   `npm run build`, and it is baked into the bundle. If the repo reads a different
   variable name, the page comes up empty with a perfectly healthy API — the
   `grep -ro 'theses.lab.invalid' dist/assets/` in §7 is there to catch exactly
   that before you discover it in a browser.
5. **`seed.sh` on `leaves` and `nurse`.** It fills fields by type after finding the
   model. Unique constraints beyond `Thesis.numero`, required foreign keys with no
   rows to point at, or custom validators will stop it. It prints what it found
   and stops rather than guessing.
6. **`s5-04`'s determinism**, as above. It now runs against a systemd unit
   rather than a container, so the limit is a `MemoryMax=` drop-in and the OOM
   line should name `nurse-api.service`'s cgroup.
7. **`s5-07` reaching emergency mode at all.** An fstab entry with `defaults` on a
   non-root mount *should* be a hard dependency of `local-fs.target`. If 24.04
   does something gentler, the challenge needs rewriting.
8. **`s3-02` changed hands.** It was verified against a mock `docker compose`,
   but `nurse` now runs under systemd, so the branch that will execute is the
   untested one — a restart that re-reads the `EnvironmentFile` rather than a
   container recreate. It is cheap to try if you have ten minutes spare after the
   three above: `lab start s3-02-theses-api-down`, fix the port in
   `/etc/nurse/nurse.env`, `lab check`. Not required this session.
9. **Stage 7 is seven challenges and six of them are unproven.** They need a
   real restic repository, a real timer and a real second filesystem, none of
   which a container can honestly provide. Do them **in order** — s7-01 builds
   what s7-02, s7-03, s7-04, s7-05 and s7-07 all depend on, and `NEEDS` in each
   `meta` enforces that. s7-06 is `PROVEN=real`: it was verified with real cron,
   real accounts and real keys, including that its key detector does not match
   your own ed25519 key.
10. **The `clean` snapshot's `lab.conf`** is the unedited copy — `LAB_LAN_IP` is
   empty in it. If you roll back to `clean`, redo §4 before §5.
