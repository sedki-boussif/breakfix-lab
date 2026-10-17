# Break-fix lab

A training lab for three web applications. It hands out missions and incidents,
breaks things on purpose, checks the fixes, and collects the reports that make
the next one faster.

Everything runs on one disposable Ubuntu 24.04 VM with invented data. Nothing
here touches a real server, and the safety gate in `lib/guard.sh` is there to
make sure of it.

## The three apps

| App | What it is | Repo |
| --- | --- | --- |
| `stages` | Hospital-internship management: FastAPI + PostgreSQL behind nginx, two Docker networks with the back one internal, an uploads volume, a restricted database role | **stand-in** built in this repo, see `stages-lab/README.md` |
| `leaves` | Staff leave requests with HR then CEO approval: Django + Gunicorn + WhiteNoise, everything under one URL prefix | public, `leaves_management_system` at `v3.0` |
| `nurse` | A searchable catalogue of nursing theses: Django + DRF + React/Vite | public, `nurse` |

`stages` is a **stand-in** for a private application: same topology, invented
tables, no history. `STAGES_DIR` in `lab.conf` points at it, so the real app can
be dropped in later without touching a single challenge.

## Setting up the VM

`SETUP.md` builds the whole thing from a fresh Ubuntu 24.04 image: Docker,
host nginx, the three apps, fake data, and the snapshots the challenges expect.
Do that first — the lab assumes a VM it is allowed to destroy.

**For the first run, follow `FIRST-RUN.md` instead**, which is `SETUP.md` in
session order: what to have ready, where to stop and prove something before
continuing, where the two snapshots go, which challenges to validate once the
apps are up, and what to capture when a step fails.

Then:

```bash
cp lab.conf.example lab.conf   # edit the ports and paths to match your VM
export PATH="$PWD/bin:$PATH"
lab list
```

## The rules of the game

1. **Read the brief, not the code.** The brief tells you what a user noticed.
   It never tells you the cause. The challenge folder does — so stay out of it
   until you have passed.
2. **Investigate before you change anything.** The point is the diagnosis. A
   lucky fix with no explanation is a fail you have not noticed yet.
3. **Hints cost you.** `lab hint <id>` gives you one line at a time and counts
   them. A pass with four hints is honest and still a pass.
4. **Write the report.** `lab report <id>` while it is fresh. The dead ends are
   the valuable part — write them down too.
5. **The timer runs from `lab start`.** It is a measurement, not a score.
6. **Snapshot first.** Incidents ask you to confirm you have one. Two
   challenges genuinely cannot be undone and say so.

```
lab list            every challenge, with a tick when passed
lab start <id>      the brief, then the break
lab hint <id>       one more hint
lab check <id>      prove the fix
lab report <id>     write it up
lab reset <id>      undo the break
```

## Safety

No script that changes the system runs anywhere without `/etc/breakfix-lab`
containing exactly `breakfix-lab`, and `lab_guard` refuses outright on any host
whose name looks like the real server. Breaks never touch SSH access except in
the one challenge that is about that, and it requires console access. There are
no secrets, no real data and no network calls at run time in this repo. The
standing rules are in `CLAUDE.md`; the reasoning is in `BUILD-INSTRUCTIONS.md`.

## Housekeeping

```bash
make lint        shellcheck every script
make selftest    every challenge complete and well-formed
make test        break, prove the check fails, reset, prove it passes
```

`make test` refuses to run without `/etc/breakfix-lab` and `LAB_DISPOSABLE=1`,
so it cannot be aimed at a VM you care about.
