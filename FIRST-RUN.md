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

1. **`stages`** — SETUP.md §5. The long one. After `--wait` returns, all three
   services must read `(healthy)`. Then run the four topology proofs and the
   three refuse-to-start proofs in that section; they are the reason the stand-in
   exists, and they are the parts most likely to disagree with my assumptions.
2. **`leaves`** — SETUP.md §6. Note the `sudo bash -c` wrapper around the
   management commands: the env file is root-only on purpose.
3. **`nurse`** — SETUP.md §7. Run the `ls -1` check *first*: if the repo ships a
   compose file, use it; if the Dockerfile layout differs, fix the paths before
   building rather than after.

After each one, the matching line of this must answer:

```bash
curl -fsS http://127.0.0.1:8080/api/health/ ; echo    # stages
curl -fsS -o /dev/null -w 'leaves %{http_code}\n' http://127.0.0.1:8081/etoile-formation-conge/
curl -fsS http://127.0.0.1:8000/api/health/ ; echo    # nurse api
curl -fsS -o /dev/null -w 'nurse web %{http_code}\n' http://127.0.0.1:3000/
```

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
you set `restart: unless-stopped` and recreate, it passes with
`it started with the machine (Ns after boot)`. The assertion I am least sure of
is that start-time-against-boot-time comparison — record the exact numbers it
prints, pass or fail.

### 5b. `s5-04` — the API keeps dying *(no reboot, takes ~5 minutes of waiting)*

```bash
lab start s5-04-api-keeps-dying             # type yes
docker inspect -f '{{.RestartCount}}' "$(cd /opt/nurse && docker compose ps -q api)"
sudo dmesg -T | grep -iE 'oom|killed' | tail -5
lab check s5-04-api-keeps-dying             # 3 minutes of watching, then fails
# fix it, then:
lab check s5-04-api-keeps-dying
lab reset s5-04-api-keeps-dying
```

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

# --- a compose stack (stages, nurse)
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
   WSGI paths, model names, migration heads, `build.sh`, `create_default_superuser`,
   whether a Dockerfile exists where the compose file expects it — comes from what
   you told me, not from reading them. Each has a verification command next to it;
   run those rather than trusting the prose.
2. **`build.sh` in `leaves`.** I do not know what it does beyond seeding
   `rh_admin`. Read it before running it.
3. **The nurse frontend build.** `VITE_API_URL` is baked in at build time, and the
   build arg only works if that repo's Dockerfile declares `ARG VITE_API_URL`. If
   it does not, the page will come up empty with a perfectly healthy API.
4. **`seed.sh` on `leaves` and `nurse`.** It fills fields by type after finding the
   model. Unique constraints beyond `Thesis.numero`, required foreign keys with no
   rows to point at, or custom validators will stop it. It prints what it found
   and stops rather than guessing.
5. **`s5-04`'s determinism**, as above.
6. **`s5-07` reaching emergency mode at all.** An fstab entry with `defaults` on a
   non-root mount *should* be a hard dependency of `local-fs.target`. If 24.04
   does something gentler, the challenge needs rewriting.
7. **The `clean` snapshot's `lab.conf`** is the unedited copy — `LAB_LAN_IP` is
   empty in it. If you roll back to `clean`, redo §4 before §5.
