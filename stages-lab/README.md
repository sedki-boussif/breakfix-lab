# stages-lab — a stand-in, not the real application

**This is not App A.** It is a deliberately small replacement for a private
hospital-internship management application, written so this training lab can be
published and shared without the original coming with it.

Two reasons the real repository stays out:

1. Its git history still contains real student files, pending a history rewrite.
2. A stand-in keeps this lab repo publishable.

**Everything in here is invented.** Three tables, names that are obviously
placeholders, addresses at `lab.invalid`. No real trainee, member of staff or
patient has ever appeared in this database, and nothing here should ever be
pointed at a system where they could.

## What it reproduces, and why

The stand-in carries the **topology** of the real application, because that is
what the challenges exercise. It does not reproduce its features.

| Reproduced | Why the lab needs it |
| --- | --- |
| FastAPI + SQLAlchemy 2 + Alembic + PostgreSQL 16 | migrations run as one role, the app connects as another |
| nginx container in front, serving a built React/Vite bundle and proxying `/api/` | "the page loads but the API is down" is a different fault from "nothing loads" |
| Two networks, `front` and `back`, with `back` marked `internal: true` | the database has no route off the host; a challenge that claims to expose it must prove it |
| `uploads` named volume, container running as uid 10001 | ownership and mode on that path is an entire challenge (s3-05) |
| Healthchecks on all three services; `web` waits for `api` to be healthy | restart ordering, and "healthy" meaning the database answers rather than the process being alive |
| Two database roles: `stages_owner` migrates, `stages_app` connects | the app's role has `SELECT, INSERT` on `audit_log` and nothing else — append-only by permission, not by convention |
| Refuses to start in production on a placeholder `JWT_SECRET`, an empty `FORWARDED_ALLOW_IPS`, or `DEBUG=true` | the shape of a config failure that kills a container at import, not on first request |
| `placements` seeded to tens of thousands of rows, with an index on `(ward, started_on)` | dropping that index has to be *measurable* under load (s9-02), and a few hundred rows would not be |

## What it deliberately does not have

Authentication beyond a secret that must exist, PDF printing, Excel
import/export, the real schema, and any of the real application's business
rules. If a challenge needs one of those, it belongs to `leaves` or `nurse`.

## Running it

`SETUP.md` in the repo root, section 3, builds it as part of the lab VM. In
short:

```bash
cp .env.example .env     # then generate the three secrets, as the comments say
docker compose up -d --build
docker compose exec api alembic upgrade head
```

The API lands on `127.0.0.1:8080` through the `web` container. The host nginx is
what the outside world talks to; the container publishes to loopback only.

## Pointing the lab at the real app instead

Nothing in the challenges hard-codes a path. Change `STAGES_DIR` in `lab.conf`
to the real application's directory and the stage-3 and stage-5 challenges that
touch App A will work against it, provided it keeps the same service names
(`db`, `api`, `web`) or you update the `STAGES_*` service and unit names in
`lab.conf` to match.
